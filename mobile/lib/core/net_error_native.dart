import 'dart:io';
import 'package:http/http.dart' as http;

/// Зачем отдельный файл: `SocketException` живёт в `dart:io`, которого в
/// браузере нет вовсе — упоминание этого типа сломало бы веб-сборку целиком.
/// Парная версия для браузера — net_error_web.dart, сигнатура обязана совпадать.
bool isNetworkError(Object e) => e is SocketException || e is http.ClientException;


/// Отдельная функция, а НЕ расширение isNetworkError: та решает, показать ли
/// человеку «Нет подключения к серверу», и её набор менять нельзя — иначе на
/// телефоне поменялись бы тексты ошибок там, где они годами были другими.
/// Здесь же набор шире: решается лишь то, слать ли отчёт разработчику.
bool isTransportError(Object e) =>
    e is SocketException || e is HandshakeException || e is HttpException;
