import 'package:flutter/cupertino.dart';

class EmptySearchResult extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
        padding: EdgeInsets.all(16.0),
        child:
        Center(child: Text('No results found')
        )
    );
  }
}
