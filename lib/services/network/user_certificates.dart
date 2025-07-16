import 'dart:convert';
import 'dart:io';
import 'package:flutter_user_certificates_android/flutter_user_certificates_android.dart';


class UserCertificates {
  Future<SecurityContext> getContext() async {
    final ctx = SecurityContext();

    // return default if platform is not android
    if (!Platform.isAndroid){
      return ctx;
    }

    final certs = await FlutterUserCertificatesAndroid().getUserCertificates();

    // return default if no user certs
    if (certs == null) {
      return ctx;
    }

    // loop over certs and add them to context
    for (var c in certs.entries) {
      ctx.setTrustedCertificatesBytes(utf8.encode(c.value.toPEM()));
    }

    return ctx;
  }
}