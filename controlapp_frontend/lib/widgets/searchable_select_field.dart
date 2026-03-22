import 'package:flutter/material.dart';

class SearchableSelectOption<T> {
  const SearchableSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

Future<T?> showSearchableSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<SearchableSelectOption<T>> options,
  T? selectedValue,
  String searchHint = 'Buscar...',
  SearchableSelectOption<T>? clearOption,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      var query = '';

      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = options.where((option) {
            final haystack = '${option.label} ${option.subtitle ?? ''}'
                .toLowerCase();
            return haystack.contains(query.toLowerCase());
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: searchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => setState(() => query = ''),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: (value) => setState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    if (clearOption != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selectedValue == clearOption.value
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                        ),
                        title: Text(clearOption.label),
                        subtitle: clearOption.subtitle == null
                            ? null
                            : Text(clearOption.subtitle!),
                        onTap: () =>
                            Navigator.of(context).pop(clearOption.value),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay resultados para esa búsqueda.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final selected = option.value == selectedValue;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                  ),
                                  title: Text(
                                    option.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: option.subtitle == null
                                      ? null
                                      : Text(
                                          option.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onTap: () =>
                                      Navigator.of(context).pop(option.value),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class SearchableSelectField<T> extends StatelessWidget {
  const SearchableSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.prefixIcon,
    this.searchHint = 'Buscar...',
    this.placeholder = 'Seleccionar',
    this.clearLabel,
    this.clearSubtitle,
    this.enabled = true,
  });

  final String label;
  final List<SearchableSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final T? value;
  final Widget? prefixIcon;
  final String searchHint;
  final String placeholder;
  final String? clearLabel;
  final String? clearSubtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    SearchableSelectOption<T>? selected;
    for (final option in options) {
      if (option.value == value) {
        selected = option;
        break;
      }
    }

    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final picked = await showSearchableSelectionSheet<T?>(
                context: context,
                title: label,
                selectedValue: value,
                searchHint: searchHint,
                options: options
                    .map(
                      (option) => SearchableSelectOption<T?>(
                        value: option.value,
                        label: option.label,
                        subtitle: option.subtitle,
                      ),
                    )
                    .toList(),
                clearOption: clearLabel == null
                    ? null
                    : SearchableSelectOption<T?>(
                        value: null,
                        label: clearLabel!,
                        subtitle: clearSubtitle,
                      ),
              );
              onChanged(picked);
            },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: prefixIcon,
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          enabled: enabled,
        ),
        child: Text(
          selected?.label ?? placeholder,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected == null
              ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).hintColor,
                )
              : null,
        ),
      ),
    );
  }
}
