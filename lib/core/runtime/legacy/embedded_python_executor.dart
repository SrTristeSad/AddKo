import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'android_python_runtime.dart';
import 'embedded_python_host.dart';
import 'legacy_plugin_invocation.dart';
import 'legacy_plugin_result.dart';
import 'legacy_runtime_collector.dart';
import 'legacy_runtime_request.dart';
import 'python_executor.dart';
typedef EmbeddedPythonEventHandler=FutureOr<void> Function(String method,Map<String,Object?> params);
class EmbeddedPythonExecutor implements PythonExecutor{EmbeddedPythonExecutor({required this.workerScriptPath,this.requestHandler,this.eventHandler,EmbeddedPythonHost? host}):_host=host??EmbeddedPythonHost.tryOpen();final String workerScriptPath;final LegacyRuntimeRequestHandler? requestHandler;final EmbeddedPythonEventHandler? eventHandler;final EmbeddedPythonHost? _host;
@override Future<LegacyPluginResult>invoke(LegacyPluginInvocation invocation)async{final collector=LegacyRuntimeCollector();final host=_host;if(host==null){collector.consumeStderrLine('Host nativo do CPython não foi encontrado no pacote Android.');return collector.build(exitCode:-1);}AndroidPythonRuntimeInfo info;try{info=await AndroidPythonRuntime.prepare();}on Object catch(e){collector.consumeStderrLine('Falha ao preparar CPython Android: $e');return collector.build(exitCode:-2);}if(!host.hasBundledPython){collector.consumeStderrLine(host.lastError.isEmpty?'Biblioteca CPython embarcada não encontrada para ${info.abi}.':host.lastError);return collector.build(exitCode:-3);}final temp=await Directory.systemTemp.createTemp('addko-embedded-python-');final context=File('${temp.path}/context.json'),stderr=File('${temp.path}/stderr.log'),exit=File('${temp.path}/exit-code.txt');final server=await ServerSocket.bind(InternetAddress.loopbackIPv4,0,shared:false);final token=_bridgeToken();try{await context.writeAsString(jsonEncode(invocation.toJson()),flush:true);final execution=Isolate.run<Map<String,Object?>>(()=>_runEmbedded(workerPath:workerScriptPath,contextPath:context.path,stderrPath:stderr.path,exitPath:exit.path,pythonHome:info.home,port:server.port,token:token));Socket socket;try{socket=await server.first.timeout(const Duration(seconds:8));}on TimeoutException{final native=await execution;collector.consumeStderrLine(native['error']?.toString().isNotEmpty==true?native['error']!.toString():'CPython não abriu o bridge local do AddKo.');return collector.build(exitCode:(native['status'] as num?)?.toInt()??-4);}await _consumeBridge(socket,collector,token);final native=await execution;if(await stderr.exists()){for(final l in await stderr.readAsLines()){collector.consumeStderrLine(l);}}final status=(native['status'] as num?)?.toInt()??0;if(status!=0){collector.consumeStderrLine(native['error']?.toString()??'Falha no host CPython ($status).');return collector.build(exitCode:status);}final code=await exit.exists()?int.tryParse((await exit.readAsString()).trim())??0:0;return collector.build(exitCode:code);}finally{await server.close();if(await temp.exists())await temp.delete(recursive:true);}}
Future<void>_consumeBridge(Socket socket,LegacyRuntimeCollector collector,String token)async{var auth=false;try{await for(final line in socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())){if(!auth){if(line!='ADDKO_EMBEDDED $token'){collector.consumeStderrLine('Bridge CPython rejeitado: handshake inválido.');socket.destroy();return;}auth=true;continue;}final req=LegacyRuntimeRequest.tryParse(line);if(req!=null){Object? result=req.defaultValue;if(requestHandler!=null){try{result=await requestHandler!(req);}on Object catch(e){collector.consumeStderrLine('Embedded request ${req.method} failed: $e');}}socket.writeln(jsonEncode({'request_id':req.id,'result':result}));await socket.flush();continue;}await _forwardEvent(line,collector);collector.consumeStdoutLine(line);}}finally{await socket.close();}}
Future<void>_forwardEvent(String line,LegacyRuntimeCollector c)async{if(eventHandler==null||!line.startsWith(LegacyRuntimeCollector.protocolPrefix))return;try{final d=jsonDecode(line.substring(LegacyRuntimeCollector.protocolPrefix.length));if(d is! Map)return;final e=Map<String,Object?>.from(d),p=e['params'];final method=e['method']?.toString()??'';if(method.isNotEmpty)await Future<void>.sync(()=>eventHandler!(method,p is Map?Map<String,Object?>.from(p):const {}));}on Object catch(e){c.consumeStderrLine('Embedded event bridge failed: $e');}}
static Map<String,Object?>_runEmbedded({required String workerPath,required String contextPath,required String stderrPath,required String exitPath,required String pythonHome,required int port,required String token}){final h=EmbeddedPythonHost.tryOpen();if(h==null)return const {'status':-1,'error':'Host nativo do CPython não pôde ser carregado no isolate.'};if(!h.hasBundledPython)return{'status':-2,'error':h.lastError};final c=h.configure(pythonHome);if(c!=0)return{'status':c,'error':h.lastError};final i=h.initialize();if(i!=0)return{'status':i,'error':h.lastError};final status=h.executeIsolated(_bootstrapSource(workerPath:workerPath,contextPath:contextPath,stderrPath:stderrPath,exitPath:exitPath,port:port,token:token));return{'status':status,'error':status==0?'':h.lastError};}
static String _bootstrapSource({required String workerPath,required String contextPath,required String stderrPath,required String exitPath,required int port,required String token}){String lit(String v)=>jsonEncode(v);return '''
import runpy, socket, sys, traceback
_worker=${lit(workerPath)}
_context=${lit(contextPath)}
_stderr_path=${lit(stderrPath)}
_exit_path=${lit(exitPath)}
_bridge_port=$port
_bridge_token=${lit(token)}
_old_stdout=sys.stdout; _old_stderr=sys.stderr; _old_stdin=sys.stdin; _old_argv=list(sys.argv); _old_path=list(sys.path)
_exit_code=0
for _name in ('addko_bridge','addko_window','xbmc','xbmcaddon','xbmcdrm','xbmcgui','xbmcplugin','xbmcvfs'): sys.modules.pop(_name,None)
_socket=socket.create_connection(('127.0.0.1',_bridge_port),timeout=8.0)
_stdin=_socket.makefile('r',encoding='utf-8',newline='\\n'); _stdout=_socket.makefile('w',encoding='utf-8',newline='\\n',buffering=1)
_stdout.write('ADDKO_EMBEDDED '+_bridge_token+'\\n'); _stdout.flush()
with open(_stderr_path,'w',encoding='utf-8') as _stderr:
 sys.stdout=_stdout; sys.stderr=_stderr; sys.stdin=_stdin; sys.argv=[_worker,_context]
 try: runpy.run_path(_worker,run_name='__main__')
 except SystemExit as _error: _exit_code=_error.code if isinstance(_error.code,int) else 0
 except BaseException: traceback.print_exc(file=_stderr); _exit_code=1
 finally: sys.stdout=_old_stdout; sys.stderr=_old_stderr; sys.stdin=_old_stdin; sys.argv=_old_argv; sys.path[:]=_old_path
try: _stdout.close(); _stdin.close()
finally: _socket.close()
with open(_exit_path,'w',encoding='utf-8') as _handle: _handle.write(str(_exit_code))
''';}
String _bridgeToken(){final r=Random.secure();return base64Url.encode(List<int>.generate(24,(_)=>r.nextInt(256))).replaceAll('=','');}}
