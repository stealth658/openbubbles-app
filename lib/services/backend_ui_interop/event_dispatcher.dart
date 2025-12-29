import 'dart:async';

import 'package:tuple/tuple.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
EventDispatcher get EventDispatcherSvc => GetIt.I<EventDispatcher>();

class EventDispatcher {
  final StreamController<Tuple2<String, dynamic>> _stream = StreamController<Tuple2<String, dynamic>>.broadcast();
  Stream<Tuple2<String, dynamic>> get stream => _stream.stream;
  
  void close() {
    _stream.close();
  }

  void emit(String type, [dynamic data]) {
    _stream.sink.add(Tuple2(type, data));
  }
}
