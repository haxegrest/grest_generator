package grest.discovery;

import haxe.macro.Expr;
import haxe.DynamicAccess;

using tink.CoreApi;

class Discovery {
	public static function parse(json:String):Description {
		return haxe.Json.parse(json);
	}
}

@:forward
abstract Ref(Ref_) from Ref_ to Ref_ {
	public var _ref(get, set):String;
	
	inline function get__ref():String
		return Helper._get(this, "$ref");
	inline function set__ref(v:String):String
		return Helper._set(this, "$ref", v);
}

@:forward
abstract Parameter(Parameter_) from Parameter_ to Parameter_ {
	public var _ref(get, set):String;
	public var _default(get, set):String;
	public var _enum(get, set):Array<String>;
	
	public function resolveType():ResolvedType {
		switch _ref {
			case null: // continue
			case ref: return Complex(TPath({name: ref, pack: []}));
		}
		
		var ct = switch this.type {
			case 'string': macro:String;
			case 'integer': macro:Int;
			case 'number': macro:Float;
			case 'boolean': macro:Bool;
			case 'any': macro:tink.json.Value;
			case 'array':
				switch this.items.resolveType() {
					case Complex(ct): macro:Array<$ct>;
					case t: throw 'unhandled nested type $t';
				}
			case 'object': 
				switch this.additionalProperties.resolveType() {
					case Complex(ct): macro:haxe.DynamicAccess<$ct>;
					case t: throw 'unhandled nested type $t';
				}
			case v: throw 'unhandled type $v';
		}
		
		return switch _enum {
			case null: Complex(ct);
			case values: Enum(values);
		}
	}
	
	inline function get__ref():String
		return Helper._get(this, "$ref");
	inline function set__ref(v:String):String
		return Helper._set(this, "$ref", v);
	inline function get__default():String
		return Helper._get(this, "default");
	inline function set__default(v:String):String
		return Helper._set(this, "default", v);
	inline function get__enum():Array<String>
		return Helper._get(this, "enum");
	inline function set__enum(v:Array<String>):Array<String>
		return Helper._set(this, "enum", v);
	
}

private class Helper {
	public static inline function _get<T, V>(o:T, k:String):V
		return Reflect.field(o, k);
	public static inline function _set<T, V>(o:T, k:String, v:V):V {
		Reflect.setField(o, k, v);
		return v;
	}
}

enum ResolvedType {
	Complex(ct:ComplexType);
	Enum(values:Array<String>);
}

typedef Description = {
	kind:String, // "discovery#restDescription"
	discoveryVersion:String, //"v1"
	id:String,
	name:String,
	version:String,
	revision:String,
	title:String,
	description:String,
	icons: {
		x16:String,
		x32:String
	},
	documentationLink:String,
	labels:Array<String>,
	protocol:String, //"rest"
	// baseUrl:String, // deprecated
	// basePath:String, // deprecated
	rootUrl:String,
	servicePath:String,
	batchPath:String, //"batch"
	parameters:DynamicAccess<Parameter>,
	auth: {
		oauth2: {
			scopes: DynamicAccess<{description:String}>
		}
	},
	features:Array<String>,
	schemas:DynamicAccess<Parameter>,
	methods:DynamicAccess<Method>,
	resources:DynamicAccess<Resource>
}

typedef Resource = {
	methods:DynamicAccess<Method>,
	resources:DynamicAccess<Resource>,
}

typedef Ref_ = {};

typedef Method = {
	id:String,
	path:String,
	httpMethod:String,
	description:String,
	parameters:DynamicAccess<Parameter>,
	parameterOrder:Array<String>,
	request:Ref,
	response:Ref,
	scopes:Array<String>,
	supportsMediaDownload:Bool,
	supportsMediaUpload:Bool,
	mediaUpload: {
		accept:Array<String>,
		maxSize:String,
		protocols: {
			simple: {
				multipart:Bool, // true
				path:String
			},
			resumable: {
				multipart:Bool, // true
				path:String
			}
		}
	},
	supportsSubscription:Bool
}

typedef Parameter_ = {
	id:String,
	type:String,
	description:String,
	// default:String,
	required:Bool,
	format:String,
	pattern:String,
	minimum:String,
	maximum:String,
	// enum:Array<String>,
	enumDescriptions:Array<String>,
	repeated:Bool,
	location:String,
	properties:DynamicAccess<JsonSchema>,
	additionalProperties:JsonSchema,
	items:JsonSchema,
	annotations: {
		required:Array<String>
	}
}


typedef JsonSchema = Parameter;