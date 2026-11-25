import 'package:http/http.dart' as http;

bool isNetworkError(Object e) => e is http.ClientException;


bool isTransportError(Object e) => e is http.ClientException;
