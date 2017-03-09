package grest.generator;

import haxe.DynamicAccess;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
import sys.io.File;
import sys.FileSystem;
import grest.discovery.Discovery;
import tink.Cli;

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
				
				// path params
				for(p in method.parameterOrder) {
					var param = method.parameters.get(p);
					args.push({
						name: p,
						opt: !param.required,
						type: resolveComplexType(param, 'Api_' + upperFirst(sub), methodName),
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
					meta: [{
						name: ':' + method.httpMethod.toLowerCase(),
						params: [{expr: EConst(CString('/' + translatePath(method.path))), pos: null}],
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
	
	function genTypes() {
		
		for(key in description.schemas.keys()) {
			var schema = description.schemas.get(key);
			
			var fields:Array<Field> = [];
			
			for(key in schema.properties.keys()) {
				var ct = resolveComplexType(schema.properties.get(key), schema.id, key);
				
				fields.push({
					name: key,
					kind: FVar(ct),
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
	
	var pathRegex = ~/{([^}]*)}/g;
	function translatePath(v:String) {
		if(pathRegex.match(v)) return pathRegex.replace(v, "$$$1");
		return v;
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