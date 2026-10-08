#include "my_application.h"
#include <cstdint>
#include <cstring>
#include <string>

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static std::string argument_string(FlMethodCall* call, const gchar* key) {
  FlValue* args = fl_method_call_get_args(call);
  FlValue* value = fl_value_lookup_string(args, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(value)
      : std::string();
}

static FlValue* icon_png(GIcon* icon, gint size) {
  if (!icon) return nullptr;
  const gchar* const* names = G_IS_THEMED_ICON(icon)
      ? g_themed_icon_get_names(G_THEMED_ICON(icon))
      : nullptr;
  if (!names || !names[0]) return nullptr;
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (!theme) return nullptr;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = gtk_icon_theme_load_icon(
      theme, names[0], size, GTK_ICON_LOOKUP_USE_BUILTIN, &error);
  if (!pixbuf) return nullptr;
  gchar* data = nullptr;
  gsize length = 0;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &data, &length, "png", &error,
                                 nullptr)) {
    return nullptr;
  }
  FlValue* value = fl_value_new_uint8_list(reinterpret_cast<uint8_t*>(data), length);
  g_free(data);
  return value;
}

static GAppInfo* app_from_path(const gchar* path) {
  g_autoptr(GError) error = nullptr;
  return g_app_info_create_from_commandline(path, nullptr, G_APP_INFO_CREATE_NONE,
                                            &error);
}

static FlValue* application_info(GAppInfo* app, GAppInfo* preferred) {
  g_autoptr(FlValue) info = fl_value_new_map();
  fl_value_set_string_take(info, "name",
                           fl_value_new_string(g_app_info_get_display_name(app)));
  fl_value_set_string_take(info, "path",
                           fl_value_new_string(g_app_info_get_executable(app)));
  fl_value_set_string_take(info, "default", fl_value_new_bool(app == preferred));
  if (GIcon* icon = g_app_info_get_icon(app)) {
    if (FlValue* bytes = icon_png(icon, 64)) {
      fl_value_set_string_take(info, "icon", bytes);
    }
  }
  return g_steal_pointer(&info);
}

static void native_files_handler(FlMethodChannel*, FlMethodCall* call,
                                 gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  GtkWindow* window = GTK_WINDOW(user_data);
  const std::string path = argument_string(call, "path");
  if (std::strcmp(method, "fileIcon") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    const bool directory = fl_value_get_bool(fl_value_lookup_string(args, "directory"));
    const gint size = fl_value_get_int(fl_value_lookup_string(args, "pixelSize"));
    g_autofree gchar* type = directory
        ? g_strdup("inode/directory")
        : g_content_type_guess(path.c_str(), nullptr, 0, nullptr);
    g_autoptr(GIcon) icon = g_content_type_get_icon(type);
    FlValue* bytes = icon_png(icon, size > 0 ? size : 64);
    fl_method_call_respond_success(call, bytes ? bytes : fl_value_new_null(), nullptr);
    if (bytes) fl_value_unref(bytes);
    return;
  }
  g_autofree gchar* type = g_content_type_guess(path.c_str(), nullptr, 0, nullptr);
  g_autoptr(GAppInfo) preferred = g_app_info_get_default_for_type(type, false);
  if (std::strcmp(method, "defaultApplication") == 0) {
    FlValue* value = preferred ? application_info(preferred, preferred) : fl_value_new_null();
    fl_method_call_respond_success(call, value, nullptr);
    fl_value_unref(value);
    return;
  }
  if (std::strcmp(method, "applicationsForFile") == 0) {
    GList* apps = g_app_info_get_all_for_type(type);
    g_autoptr(FlValue) list = fl_value_new_list();
    for (GList* item = apps; item; item = item->next) {
      auto* app = G_APP_INFO(item->data);
      fl_value_append_take(list, application_info(app, preferred));
    }
    g_list_free_full(apps, g_object_unref);
    fl_method_call_respond_success(call, list, nullptr);
    return;
  }
  if (std::strcmp(method, "openWith") == 0) {
    const std::string app_path = argument_string(call, "application");
    g_autoptr(GAppInfo) app = app_from_path(app_path.c_str());
    g_autoptr(GFile) file = g_file_new_for_path(path.c_str());
    g_autoptr(GList) files = g_list_prepend(nullptr, file);
    g_autoptr(GError) error = nullptr;
    const gboolean launched = app && g_app_info_launch(app, files, nullptr, &error);
    g_list_free(files);
    if (!launched) {
      fl_method_call_respond_error(call, "open_application",
                                   error ? error->message : "Cannot open application",
                                   nullptr, nullptr);
    } else {
      fl_method_call_respond_success(call, nullptr, nullptr);
    }
    return;
  }
  if (std::strcmp(method, "chooseApplication") == 0) {
    GtkWidget* dialog = gtk_app_chooser_dialog_new(window, GTK_DIALOG_MODAL,
                                                    g_file_new_for_path(path.c_str()));
    const gint response = gtk_dialog_run(GTK_DIALOG(dialog));
    GAppInfo* app = response == GTK_RESPONSE_OK
        ? gtk_app_chooser_get_app_info(GTK_APP_CHOOSER(dialog))
        : nullptr;
    FlValue* value = app ? application_info(app, preferred) : fl_value_new_null();
    fl_method_call_respond_success(call, value, nullptr);
    fl_value_unref(value);
    if (app) g_object_unref(app);
    gtk_widget_destroy(dialog);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gboolean hide_auxiliary_window_on_delete(GtkWidget* widget,
                                                GdkEvent* event,
                                                gpointer user_data) {
  gtk_widget_hide(widget);
  return TRUE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "hizip");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "hizip");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  auto* registrar = fl_plugin_registry_get_registrar_for_plugin(
      FL_PLUGIN_REGISTRY(view), "DesktopMultiWindowPlugin");
  auto* codec = fl_standard_method_codec_new();
  auto* native_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "dev.hizip/native_files",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      native_channel, native_files_handler, window, nullptr);
  g_object_unref(codec);
  g_object_unref(native_channel);
  g_object_unref(registrar);
  desktop_multi_window_plugin_set_window_created_callback([](FlPluginRegistry* registry) {
    fl_register_plugins(registry);
    auto* registrar = fl_plugin_registry_get_registrar_for_plugin(registry, "HiZipTaskHost");
    auto* child_view = fl_plugin_registrar_get_view(registrar);
    auto* child_window = gtk_widget_get_toplevel(GTK_WIDGET(child_view));
    if (GTK_IS_WINDOW(child_window)) {
      g_signal_connect(child_window, "delete-event",
                       G_CALLBACK(hide_auxiliary_window_on_delete), nullptr);
    }
    auto* codec = fl_standard_method_codec_new();
    auto* channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
      "dev.hizip/task-window-host", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel, [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
      auto* host = gtk_widget_get_toplevel(GTK_WIDGET(data));
      auto* value = fl_value_new_int(reinterpret_cast<intptr_t>(host));
      fl_method_call_respond_success(call, value, nullptr);
      fl_value_unref(value);
    }, child_view, nullptr);
    g_object_unref(codec);
    g_object_unref(channel);
    g_object_unref(registrar);
  });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
