import 'package:flutter/material.dart';

/// App-wide input helpers so we don't repeat config everywhere.
class AppInputs {
  /// Default TextField: words capitalization, suggestions, autocorrect.
  static Widget textField({
    required TextEditingController controller,
    String? label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    bool obscureText = false,
    int? maxLines = 1,
    FocusNode? focusNode, // ✅ added
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    Widget? prefixIcon,
    Widget? suffixIcon,
    InputDecoration? decoration,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode, // ✅ wired in
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.words, // ✅ auto-cap words
      autocorrect: true,
      enableSuggestions: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration:
          decoration ??
          InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
    );
  }

  /// Same defaults for TextFormField (when using forms/validation).
  static Widget textFormField({
    required TextEditingController controller,
    String? label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    bool obscureText = false,
    int? maxLines = 1,
    FocusNode? focusNode, // ✅ added
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    String? Function(String?)? validator,
    Widget? prefixIcon,
    Widget? suffixIcon,
    InputDecoration? decoration,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode, // ✅ wired in
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.words, // ✅ auto-cap words
      autocorrect: true,
      enableSuggestions: true,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration:
          decoration ??
          InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
    );
  }

  /// Optional helper if you ever want to force Title Case on save.
  static String toTitleCase(String input) {
    return input
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
