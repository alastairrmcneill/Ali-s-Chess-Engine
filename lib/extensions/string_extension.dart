// ignore_for_file: unused_local_variable

extension StringExtension on String {
  bool isUpperCase() {
    return this == this.toUpperCase();
  }

  bool isNumeric() {
    try {
      var value = int.parse(this);
    } on FormatException {
      return false;
    }
    return true;
  }
}
