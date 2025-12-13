import 'dart:isolate';

bool isIsolate() {
  print('[ENV] Isolate check: ${Isolate.current.debugName}');
  return Isolate.current.debugName != null && Isolate.current.debugName != 'main';
}