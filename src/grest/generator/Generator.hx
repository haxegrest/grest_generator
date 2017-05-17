package grest.generator;

import haxe.DynamicAccess;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
import sys.io.File;
import sys.FileSystem;
import grest.discovery.Discovery;
import tink.Cli;
import tink.Url;

using StringTools;
using Lambda;

class Command {
	public function new() {}
	
	public var output:String;
	
	@:defaultCommand
	public function run(path:String) {
		new Generator(sys.io.File.getContent(path), output).generate();
	}
}

class Generator {
	static function main() {
		var sms = js.Lib.require('source-map-support');
		sms.install();
		haxe.CallStack.wrapCallSite = sms.wrapCallSite;
		Cli.process(Sys.args(), new Command()).handle(Cli.exit);
	}
	
	var description:Description;
	var name:String;
	var version:String;
	var pack:Array<String>;
	var typesPack:Array<String>;
	var apiPack:Array<String>;
	var printer = new Printer();
	var output:String;
	
	public function new(json:String, out:String) {
		description = Discovery.parse(json);
		name = description.name;
		version = description.version;
		pack = ['grest', name, version];
		typesPack = pack.concat(['types']);
		apiPack = pack.concat(['api']);
		output = out;
	}
	
	public function generate() {
		genTypes();
		var fields = genMethods(description.resources);
		for(key in fields.keys()) {
			var localPack = key.split('.');
			var className = switch localPack.pop() {
				case '': upperFirst(name);
				case v: upperFirst(v);
			}
			
			writeTypeDefinition({
				name: className,
				pack: apiPack.concat(localPack),
				pos: null,
				kind: TDClass(null, null, true),
				fields: fields[key],
			});
		}
	}
	
	function genMethods(resources:DynamicAccess<Resource>, ?fields:InterfaceMap) {
		if(fields == null) fields = new InterfaceMap();
		
		for(key in resources.keys()) {
			var resource = resources.get(key);
			for(key in resource.methods.keys()) {
				var method = resource.methods.get(key);
				var pack = method.id.split('.');
				var methodName = pack.pop();
				pack.shift(); // rip off api name
				var sub = pack[pack.length - 1];
				
				
				
				var args:Array<FunctionArg> = [];
				
				var path = processPath(method.path, method.id.replace('.', '_'));
				
				// path params
				for(param in path.params) {
					args.push({
						name: param.name,
						opt: !method.parameters.get(param.name).required,
						type: param.type,
					});
				}
				// query params
				var queries:Array<Field> = [];
				for(key in method.parameters.keys()) {
					var param = method.parameters.get(key);
					if(param.location == 'query') {
						queries.push({
							name: key,
							kind: FVar(resolveComplexType(param, 'Api_' + upperFirst(sub) + '_$methodName', key)),
							doc: param.description,
							meta: param.required ? [] : [{name: ':optional', pos: null}],
							pos: null,
						});
					}
				}
				if(queries.length > 0) args.push({
					name: 'query',
					type: TAnonymous(queries),
				});
				
				// body
				if(method.request != null) {
					args.push({
						name: 'body',
						type: TPath({
							name: method.request._ref,
							pack: typesPack,
						}),
					});
				}
				
				fields.add(pack, {
					name: methodName,
					kind: FFun({
						args: args,
						expr: null,
						ret: TPath({
							name: method.response._ref,
							pack: typesPack,
						}),
					}),
					doc: method.description,
					meta: [{
						name: ':' + method.httpMethod.toLowerCase(),
						params: [{expr: EConst(CString(normalize(description.servicePath, path.path))), pos: null}],
						pos: null,
					}],
					pos: null,
				});
				
				// check parent
				var parent = pack.slice(0, pack.length - 1);
				if(!fields.has(parent, sub)) {
					fields.add(parent, {
						name: sub,
						kind: FVar(TPath({name: upperFirst(sub), pack: apiPack.concat(parent)})),
						meta: [{name: ':sub', params:[{expr: EConst(CString('/')), pos: null}], pos: null}],
						pos: null,
					});
				}
			}
			if(resource.resources != null) genMethods(resource.resources, fields);
		}
		
		return fields;
	}
	
	function normalize(base:String, path:String) {
		var path = if(base == null) path else '$base/$path';
		return haxe.io.Path.normalize(if(path.charCodeAt(0) == '/'.code) path else '/$path');
	}
	
	function genTypes() {
		
		var apiName = description.name.charAt(0).toUpperCase() + description.name.substr(1);
		var ct = TPath({name: apiName, pack: apiPack});
		var url = Url.parse(description.rootUrl);
		var host = {expr: EConst(CString(url.host.name)), pos: null};
		var port = {expr: switch url.host.port {
			case null: EConst(CIdent('null'));
			case port: EConst(CInt(Std.string(port)));
		}, pos: null};
		var api = macro class $apiName {
			public static function api(auth:grest.Authenticator, client:tink.http.Client) {
				return new tink.web.proxy.Remote<$ct>(
					new grest.AuthedClient(auth, client),
					new tink.web.proxy.Remote.RemoteEndpoint(new tink.url.Host($host, $port))
				);
			}
		}
		api.pack = pack;
		writeTypeDefinition(api);
		
		for(key in description.schemas.keys()) {
			var schema = description.schemas.get(key);
			
			var fields:Array<Field> = [];
			
			for(key in schema.properties.keys()) {
				var param = schema.properties.get(key);
				var ct = resolveComplexType(param, schema.id, key);
				
				fields.push({
					name: key,
					kind: FVar(ct),
					doc: param.description,
					pos: null,
					meta: [{name: ':optional', pos: null}],
				});
			}
			
			writeTypeDefinition({
				name: key,
				pack: typesPack,
				pos: null,
				kind: TDStructure,
				fields: fields,
			});
		}
	}
	
	function upperFirst(s:String) {
		return s.substr(0, 1).toUpperCase() + s.substr(1);
	}
	
	
	function writeTypeDefinition(def:TypeDefinition) {
		var folder = output + '/' + def.pack.join('/');
		if(!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
		File.saveContent('$folder/${def.name}.hx', printer.printTypeDefinition(def));
	}
	
	function resolveComplexType(v:Parameter, name, key) {
		return switch v.resolveType() {
			case Complex(ct):
				ct;
			case Enum(values):
				var enumName = name + '_' + key;
				writeTypeDefinition({
					name: enumName,
					pack: typesPack,
					pos: null,
					kind: TDAbstract(macro:String, [macro:String], [macro:String, macro:tink.Stringly]),
					meta: [{name: ':enum', pos: null}],
					fields: values.map(function(v):Field return {
						name: v,
						kind: FVar(null, {expr: EConst(CString(v)), pos: null}),
						pos: null,
					}),
				});
				TPath({name: enumName, pack: typesPack});
		}
	}
}
