// Conditional export: uses web WYSIWYG editor on Flutter Web,
// falls back to plain TextFormField on other platforms.
export 'rich_editor_stub.dart'
    if (dart.library.html) 'rich_editor_web.dart';
