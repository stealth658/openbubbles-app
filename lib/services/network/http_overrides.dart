import 'package:bluebubbles/helpers/helpers.dart';
import 'package:universal_io/io.dart';

bool hasBadCert = false;

class BadCertOverride extends HttpOverrides {
  @override
  createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // If there is a bad certificate callback, override it if the host is part of
      // your server URL
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        String serverUrl = sanitizeServerAddress() ?? "";
        
        // Extract hostname from the server URL
        Uri? uri = Uri.tryParse(serverUrl);
        if (uri == null) {
          hasBadCert = false;
          return false;
        }
        
        String serverHost = uri.host;
        bool isValidCert = false;
        
        // Handle wildcard certificates
        if (host.startsWith("*")) {
          // Extract the domain from wildcard (e.g., "*.example.com" -> "example.com")
          String domain = host.substring(2); // Remove "*."
          // Check if server host ends with the domain and has exactly one more subdomain
          // or matches the domain exactly
          isValidCert = serverHost == domain || 
                       (serverHost.endsWith('.$domain') && 
                        serverHost.substring(0, serverHost.length - domain.length - 1).split('.').length == 1);
        } else {
          // For non-wildcard certificates, the hosts must match exactly
          isValidCert = serverHost == host;
        }
        
        // If cert is valid (hosts match), don't override (return false)
        // If cert is invalid (hosts don't match), override and accept anyway (return true) - this is the "bad cert override"
        hasBadCert = !isValidCert;
        return hasBadCert;
      };
  }
}