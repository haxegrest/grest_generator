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
	var printer = new Printer();
	var output:String;
	
	public function new(json:String, out:String) {
		description = Discovery.parse(json);
		name = description.name;
		version = description.version;
		pack = ['grest', name, version];
		output = out;
	}
	
	public function generate() {
		genTypes();
		genMethods(description.resources);
	}
	
	function genMethods(resources:DynamicAccess<Resource>) {
		for(key in resources.keys()) {
			var resource = resources.get(key);
			for(key in resource.methods.keys()) {
				var method = resource.methods.get(key);
				var pack = method.id.split('.');
				if(pack.shift() != name) throw 'Invalid method ID: ${method.id}. Expected first section to match api name "$name"';
				var methodName = pack.pop();
				var className = upperFirst(pack.pop());
				
				trace(method.id, method.path, method.httpMethod);
			}
			if(resource.resources != null) genMethods(resource.resources);
		}
	}
	
	function genTypes() {
		
		var pack = pack.concat(['types']);
		
		for(key in description.schemas.keys()) {
			var schema = description.schemas.get(key);
			
			var fields:Array<Field> = [];
			
			for(key in schema.properties.keys()) {
				var ct = switch schema.properties.get(key).resolveType() {
					case Complex(ct):
						ct;
					case Enum(values):
						var enumName = schema.id + '_' + key;
						writeTypeDefinition({
							name: enumName,
							pack: pack,
							pos: null,
							kind: TDAbstract(macro:String, [macro:String], [macro:String, macro:tink.Stringly]),
							meta: [{name: ':enum', pos: null}],
							fields: values.map(function(v):Field return {
								name: v,
								kind: FVar(null, {expr: EConst(CString(v)), pos: null}),
								pos: null,
							}),
						});
						TPath({name: enumName, pack: []});
				}
				
				fields.push({
					name: key,
					kind: FVar(ct),
					pos: null,
					meta: [{name: ':optional', pos: null}],
				});
			}
			
			writeTypeDefinition({
				name: key,
				pack: pack,
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
}