package grest.generator;

import haxe.DynamicAccess;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
import sys.io.File;
import sys.FileSystem;
import grest.discovery.*;
import grest.discovery.types.*;
import tink.Cli;
import tink.Url;

using tink.CoreApi;
using StringTools;
using Lambda;

class Command {
	public function new() {}
	
	public var output:String;
	
	@:defaultCommand
	public function run(url:String) {
		return new grest.discovery.Description(url).get()
			.next(description -> {
				new Generator(description, output).generate();
				Noise;
			});
	}
	
	@:command
	public function all() {
		return new grest.discovery.Directory().apis()
			.next(v -> [for(item in v.items) if(item.preferred) item.discoveryRestUrl])
			// .next(v -> v.filter(url -> url != "https://baremetalsolution.googleapis.com/$discovery/rest?version=v1")) // somehow this gives a 403 error)
			.next(urls -> {
				Future.inParallel(urls.map(url -> {
					new grest.discovery.Description(url).get()
						.next(description -> {
							new Generator(description, output).generate();
							Noise;
						});
				}));
			});
	}
}

class Generator {
	static function main() {
		#if nodejs
		var sms = js.Lib.require('source-map-support');
		sms.install();
		haxe.NativeStackTrace.wrapCallSite = sms.wrapCallSite;
		#end
		Cli.process(Sys.args(), new Command()).handle(Cli.exit);
	}
	
	var description:RestDescription;
	var name:String;
	var version:String;
	var pack:Array<String>;
	var typesPack:Array<String>;
	var apiPack:Array<String>;
	var printer = new Printer();
	var output:String;
	
	public function new(description, out:String) {
		this.description = description;
		name = description.name;
		trace(name);
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
			if(resource.methods != null) for(key in resource.methods.keys()) {
				var method = resource.methods.get(key);
				var pack = method.id.split('.');
				var methodName = pack.pop();
				pack.shift(); // rip off api name
				var sub = switch pack[pack.length - 1] {
					case null: 'root';
					case v: v;
				}
				
				var args:Array<FunctionArg> = [];
				
				var path = processPath(method.path, method.id.replace('.', '_'));
				
				// path params
				for(param in path.params) {
					final name = sanitizePathParam(param.name);
					args.push({
						name: name,
						opt: !method.parameters.get(name).required,
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
							name: method.request.ref,
							pack: typesPack,
						}),
					});
				}
				
				fields.add(pack, {
					name: methodName,
					kind: FFun({
						args: args,
						expr: null,
						ret: switch method.response {
							case null:
								macro:Void;
							case res: 
								TPath({
									name: method.response.ref,
									pack: typesPack,
								});
						},
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
	
	static function normalize(base:String, path:String) {
		var path = if(base == null) path else '$base/$path';
		return haxe.io.Path.normalize(if(path.charCodeAt(0) == '/'.code) path else '/$path');
	}
	
	static function sanitizePathParam(v:String) {
		return v.charCodeAt(0) == '+'.code ? v.substr(1) : v;
	}
	
	function genTypes() {
		
		var apiName = description.name.charAt(0).toUpperCase() + description.name.substr(1);
		var ct = TPath({name: apiName, pack: apiPack});
		var url = {expr: EConst(CString(description.rootUrl)), pos: null}
		var api = macro class $apiName {
			public function new(auth:grest.Authenticator, ?client:tink.http.Client) {
				if(client == null) client = tink.http.Fetch.getClient(Default);
				this = tink.Web.connect(($url:$ct), {client: new grest.AuthedClient(auth, client)});
			}
		}
		var underlying = macro:tink.web.proxy.Remote<$ct>;
		api.meta = [{name: ':forward', pos: null}];
		api.kind = TDAbstract(underlying, [underlying], [underlying]);
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
	
	var pathRegex = ~/\{([^}]*)\}(.*)/g;
	function processPath(v:String, method:String) {
		
		var params = [];
		
		var parts = v.split('/').map(function(part) {
			return if(pathRegex.match(part)) {
				var param = sanitizePathParam(pathRegex.matched(1));
				switch pathRegex.matched(2) {
					case null | '':
						params.push({name: param, type: macro:String});
					case cmd:
						var clsname = 'Api_${method}_${param}_Command';
						var tp = {name: clsname, pack: typesPack};
						var cmdExpr = {expr: EConst(CString(cmd)), pos: null};
						var def = macro class $clsname {
							inline function new(v:String) this = v;
							@:from public static inline function fromString(v:String)
								return new $tp(v + $cmdExpr);
						}
						def.pack = typesPack;
						def.kind = TDAbstract(macro:String, [], [macro:String, macro:tink.Stringly]);
						writeTypeDefinition(def);
						params.push({name: param, type: TPath(tp)});
				}
				
				"$" + param;
			} else
				part;
		});
		
		return {path: parts.join('/'), params: params};
	}
	
	function writeTypeDefinition(def:TypeDefinition) {
		var folder = output + '/' + def.pack.join('/');
		if(!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
		File.saveContent('$folder/${def.name}.hx', printer.printTypeDefinition(def));
	}
	
	function resolveType(v:Parameter):ResolvedType {
		switch v.ref {
			case null: // continue
			case ref: return Complex(TPath({name: ref, pack: []}));
		}
		
		var ct = switch v.type {
			case 'string': macro:String;
			case 'integer': macro:Int;
			case 'number': macro:Float;
			case 'boolean': macro:Bool;
			case 'any': macro:tink.json.Value;
			case 'array':
				switch resolveType(v.items) {
					case Complex(ct): macro:Array<$ct>;
					case Enum(_): macro:Array<String>; // TODO: build a enum abstract
				}
			case 'object':
				if(v.additionalProperties != null) {
					switch resolveType(v.additionalProperties) {
						case Complex(ct): macro:haxe.DynamicAccess<$ct>;
						case Enum(_): macro:haxe.DynamicAccess<String>; // TODO: build a enum abstract
					}
				} else if(v.properties != null) {
					TAnonymous([for(key in v.properties.keys()) {
						name: key,
						kind: FVar(switch resolveType(v.properties.get(key)) {
							case Complex(ct): ct;
							case Enum(_): macro:String; // TODO: build a enum abstract
						}),
						pos: null,
					}]);
				} else {
					throw 'Expected `additionalProperties` or `properties` in an "object"';
				}
			case v: throw 'unhandled type $v';
		}
		
		return switch v.enum_ {
			case null: Complex(ct);
			case values: Enum(values);
		}
	}
	
	function resolveComplexType(v:Parameter, name, key) {
		return switch resolveType(v) {
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

@:forward(keys)
abstract InterfaceMap(Map<String, Array<Field>>) {
	public inline function new()
		this = new Map();
		
	public function add(pack:Array<String>, field:Field) {
		var key = pack.join('.');
		if(!this.exists(key)) this[key] = [];
		this[key].push(field);
	}
	
	public function has(pack:Array<String>, field:String) {
		var key = pack.join('.');
		return this.exists(key) && this[key].find(function(f) return f.name == field) != null;
	}
	
	@:arrayAccess
	public inline function _get(k:String):Array<Field>
		return this[k];
		
	@:arrayAccess
	public inline function _set(k:String, v:Array<Field>):Array<Field>
		return this[k] = v;
}

enum ResolvedType {
	Complex(ct:ComplexType);
	Enum(values:Array<String>);
}