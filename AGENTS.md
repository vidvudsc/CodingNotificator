# Coding Notificator agent notes

- Do not run Xcode scheme-wide tests, macOS UI tests, or other test runners that launch the app. The UI test runner switched this machine from Dark Mode to Light Mode, and the user asked not to run those tests again.
- For routine verification, use Swift syntax or type checks and static code review. Do not change macOS appearance.
