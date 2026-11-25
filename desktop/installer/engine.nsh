; ═════════════════════════════════════════════════════════════════════════════
; ДОБАВКИ К УСТАНОВЩИКУ-ДВИЖКУ (NSIS electron-builder, glitch-engine.exe).
;
; Две записи программа делает в разделе пользователя сама, с путём к себе:
;   * схема ссылок `glitch://` — при каждом запуске (src/main/links.ts,
;     app.setAsDefaultProtocolClient);
;   * автозапуск с Windows — когда человек включил его в разделе «Система»
;     (src/main/system-settings.ts, app.setLoginItemSettings): значение
;     с именем ${APP_ID} в «Run» и пометка «включено» для «Диспетчера задач»
;     в «StartupApproved\Run». APP_ID движок берёт из package.json (build.appId)
;     — то же имя, под которым программа пишет запись.
; Здесь — парное снятие: удалили Glitch через «Параметры → Приложения» —
; Windows больше не отдаёт `glitch://` и не запускает при входе программу,
; которой нет. При ОБНОВЛЕНИИ (старый деинсталлятор запускается перед новой
; установкой) ничего не трогаем — новая версия на том же месте, а выбор
; человека про автозапуск должен пережить обновление.
; ═════════════════════════════════════════════════════════════════════════════

!macro customUnInstall
  ${ifNot} ${isUpdated}
    DeleteRegKey HKCU "Software\Classes\glitch"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APP_ID}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" "${APP_ID}"
  ${endIf}
!macroend
