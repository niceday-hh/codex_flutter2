import 'package:flutter/services.dart';
String niceError(Object e) => e is PlatformException ? e.message ?? '操作失败，请重试' : '操作失败：$e';
