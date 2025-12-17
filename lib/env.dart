import 'dart:isolate';

bool get isIsolate => Isolate.current.debugName != null && Isolate.current.debugName != 'main';