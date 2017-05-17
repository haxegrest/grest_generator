package grest.generator;

import haxe.macro.Expr;
import haxe.macro.Printer;
import sys.FileSystem;
import sys.io.File;

class Writer {
	
	var printer = new Printer();
	
	public function new() {}
	
	public function write(basePath:String, types:Array<TypeDefinition>) {
		for(type in types) {
			writeTypeDefinition(basePath, type);
		}
	}
	
	function writeTypeDefinition(basePath:String, def:TypeDefinition) {
		var folder = basePath + '/' + def.pack.join('/');
		if(!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
		File.saveContent('$folder/${def.name}.hx', printer.printTypeDefinition(def));
	}
}