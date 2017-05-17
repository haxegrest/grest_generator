package grest.generator;

import haxe.macro.Expr;
import haxe.DynamicAccess;
import grest.discovery.Discovery;

using Lambda;
using StringTools;

class Types {
	
	public static function generate(info)
		return new Types(info)._generate();
	
	var info:Info;
	var apiPack:Array<String>;
	var typesPack:Array<String>;
	var types:Map<String, TypeDefinition>;
	var methods:Map<String, {pack:Array<String>, field:Field}>;
	var enums:Array<EnumType>;
	
	function new(info) {
		this.info = info;
		
		types = new Map();
		methods = new Map();
		apiPack = info.apiPack;
		typesPack = info.typesPack;
		enums = [];
	}
	
	function _generate() {
		genSchemas();
		genMethods(info.resources);
		
		return {
			types: types,
			methods: methods,
		}
	}
	
	function genSchemas() {
		for(key in info.schemas.keys()) {
			var schema = info.schemas.get(key);
			
			var fields:Array<Field> = [];
			
			for(key in schema.properties.keys()) {
				var param = schema.properties.get(key);
				var ct = resolveType(param);
				
				fields.push({
					name: key,
					kind: FVar(ct),
					doc: param.description,
					pos: null,
					meta: [{name: ':optional', pos: null}],
				});
			}
			
			storeTypeDefinition({
				name: key,
				pack: typesPack,
				pos: null,
				kind: TDStructure,
				fields: fields,
			});
		}
	}
	
	function genMethods(resources:DynamicAccess<Resource>) {
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
							kind: FVar(resolveType(param)),
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
				
				methods.add({
					pack: pack,
					field:{
						name: methodName,
						kind: FFun({
							args: args,
							expr: null,
							ret: TPath({
								name: method.response.ref,
								pack: typesPack,
							}),
						}),
						doc: method.description,
						meta: [{
							name: ':' + method.httpMethod.toLowerCase(),
							params: [{expr: EConst(CString(normalize(info.servicePath, path.path))), pos: null}],
							pos: null,
						}],
						pos: null,
					}
				});
				
			}
			if(resource.resources != null) genMethods(resource.resources);
		}
	}
	
	function upperFirst(s:String) {
		return s.substr(0, 1).toUpperCase() + s.substr(1);
	}
	
	function resolveType(v:Parameter):ComplexType {
		switch v.ref {
			case null: // continue
			case ref: return TPath({name: ref, pack: []});
		}
		
		switch v.enum_ {
			case null: // continue
			case values: 
				var type = new EnumType(values);
				var index = switch enums.indexOf(type) {
					case -1:
						enums.push(type);
						var i = enums.length - 1;
						var name = 'Enum$i';
						storeTypeDefinition({
							name: name,
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
						i;
					
					case i:
						i;
				}
				return TPath({name: 'Enum$index', pack: typesPack});
				
		}
		
		return switch v.type {
			case 'string': macro:String;
			case 'integer': macro:Int;
			case 'number': macro:Float;
			case 'boolean': macro:Bool;
			case 'any': macro:tink.json.Value;
			case 'array':
				var ct = resolveType(v.items);
				macro:Array<$ct>;
				
			case 'object':
				if(v.additionalProperties != null) {
					var ct = resolveType(v.additionalProperties);
					macro:haxe.DynamicAccess<$ct>;
				} else if(v.properties != null) {
					TAnonymous([for(key in v.properties.keys()) {
						name: key,
						kind: FVar(resolveType(v.properties.get(key))),
						pos: null,
					}]);
				} else {
					throw 'Expected `additionalProperties` or `properties` in an "object"';
				}
			case v: throw 'unhandled type $v';
		}
	}
	
	function normalize(base:String, path:String) {
		var path = if(base == null) path else '$base/$path';
		return haxe.io.Path.normalize(if(path.charCodeAt(0) == '/'.code) path else '/$path');
	}
	
	var pathRegex = ~/{([^}]*)}(.*)/g;
	function processPath(v:String, method:String) {
		
		var params = [];
		
		var parts = v.split('/').map(function(part) {
			return if(pathRegex.match(part)) {
				var param = pathRegex.matched(1);
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
						storeTypeDefinition(def);
						params.push({name: param, type: TPath(tp)});
				}
				
				"$" + param;
			} else
				part;
		});
		
		return {path: parts.join('/'), params: params};
	}
	
	function storeTypeDefinition(def:TypeDefinition) {
		types.set(def.pack.concat([def.name]).join('.'), def);
	}
}


abstract EnumType(String) to String {
	public function new(values:Array<String>) {
		var copy = values.copy();
		copy.sort(Reflect.compare);
		this = copy.join(',');
	}
}


@:forward(keys)
abstract MethodMap(Map<String, Array<Field>>) {
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