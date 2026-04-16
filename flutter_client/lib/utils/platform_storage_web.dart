// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Read a value from browser localStorage.
String? storageGet(String key) => html.window.localStorage[key];

/// Write a value to browser localStorage.
void storageSet(String key, String value) {
  html.window.localStorage[key] = value;
}

/// Remove a value from browser localStorage.
void storageRemove(String key) {
  html.window.localStorage.remove(key);
}
