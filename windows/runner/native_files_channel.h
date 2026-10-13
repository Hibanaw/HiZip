#ifndef RUNNER_NATIVE_FILES_CHANNEL_H_
#define RUNNER_NATIVE_FILES_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

// Registers the dev.hizip/native_files channel's Windows handlers for file
// icons and "open with"/default-application queries: fileIcon,
// defaultApplication, applicationsForFile, openWith, chooseApplication.
// Mirrors macOS's HizipNativePlugin.swift and Linux's my_application.cc.
// |owner| is used as the parent window for the "choose application" picker.
void RegisterNativeFilesChannel(flutter::BinaryMessenger* messenger,
                                HWND owner);

#endif  // RUNNER_NATIVE_FILES_CHANNEL_H_
