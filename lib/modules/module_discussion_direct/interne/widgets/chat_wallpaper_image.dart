import 'package:flutter/widgets.dart';
import 'chat_wallpaper_image_stub.dart'
    if (dart.library.io) 'chat_wallpaper_image_io.dart' as platform;

Widget buildChatWallpaperImage(String path, {required Key key}) =>
    platform.buildChatWallpaperImage(path, key: key);
