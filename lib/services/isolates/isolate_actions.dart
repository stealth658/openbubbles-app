import 'package:bluebubbles/services/isolates/actions/test_action.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class IsolateActons {
  static final Map<IsolateRequestType, dynamic> actions = {
    // Testing
    IsolateRequestType.testReturnInput: TestAction.executeTestReturnInput,
    IsolateRequestType.testPrintInput: TestAction.executeTestPrintInput,
    IsolateRequestType.testThrowError: TestAction.executeTestThrowError,
  };
}
