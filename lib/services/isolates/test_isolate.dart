import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class TestIsolate {
  static void testReturnInput() async {
    final isolate = GetIt.I<GlobalIsolate>();
    final response = await isolate.send(IsolateRequestType.testReturnInput, input: 'Hello from TestIsolate');
    Logger().info('Response from isolate: $response');
  }
}
