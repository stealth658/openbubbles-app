import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_bar_ios.dart';
import 'package:flutter/material.dart';

class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final bool iOS;

  const SettingsSearchBar({super.key, this.onChanged, required this.iOS});

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  String searchValue = '';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // sync the controller text when widget changes
    _controller.text = searchValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: widget.iOS
          ? SettingsSearchBariOS(
        // use cupertino search bar if iOS style
        controller: _controller,
        focusNode: _focusNode,
        onChanged: (query) {
          setState(() {
            searchValue = query.toLowerCase();
          });
          widget.onChanged?.call(searchValue);
        },
      )
          : SearchBar(
        // material themed search bar
        controller: _controller,
        focusNode: _focusNode,
        hintText: 'Search Settings',
        hintStyle: MaterialStateProperty.all(
          TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.5)
                : Colors.black.withOpacity(0.5),
          ),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(horizontal: 16.0),
        ),
        elevation: const MaterialStatePropertyAll(1),
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
                    _focusNode.unfocus();
                  });
                  widget.onChanged?.call('');
                },
                icon: const Icon(Icons.clear),
              ),
            ),
        ],
      ),
    );
  }
}
