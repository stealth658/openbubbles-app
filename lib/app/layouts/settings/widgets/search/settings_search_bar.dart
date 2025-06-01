import 'package:flutter/material.dart';

class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;

  const SettingsSearchBar({super.key, this.onChanged});

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  String searchValue = '';
  final SearchController _controller = SearchController();
  final FocusNode _focusNode = FocusNode(); // add focus node

  @override
  void dispose() {
    _focusNode.dispose(); // clean up focus node
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus(); // dismiss keyboard if tapped outside
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SearchBar(
          controller: _controller,
          focusNode: _focusNode, // connect the focus node
          hintText: 'Search Settings',
          hintStyle: MaterialStateProperty.all(
              TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.5)
                    : Colors.black.withOpacity(0.5),
              )
          ),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16.0),
          ),
          elevation: const MaterialStatePropertyAll(1),
          onTap: () {
            // Optional: expand search or open a view
          },
          onChanged: (query) {
            setState(() {
              searchValue = query.toLowerCase();
            });
            widget.onChanged?.call(searchValue);
          },
          leading: const Icon(Icons.search),
          trailing: <Widget>[
            if (searchValue.isNotEmpty)
              Tooltip(
                message: 'Clear search',
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      searchValue = '';
                      _controller.text = '';
                      _focusNode.unfocus(); // remove focus when cleared
                    });
                    widget.onChanged?.call('');
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
