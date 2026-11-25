/// model-viewer из model_viewer_plus 1.9.3 держит фокус на .userInput
/// внутри Shadow DOM. Убираем только браузерную рамку этой поверхности;
/// tabindex и события управления остаются у движка.
const achievementModelFocusCss = '''
.userInput:focus,
.userInput:focus-visible {
  outline: none;
}
''';
