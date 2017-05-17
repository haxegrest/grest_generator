package grest.generator;

import grest.discovery.Discovery;

@:forward
abstract Info(Description) from Description to Description {
	public var pack(get, never):Array<String>;
	public var apiPack(get, never):Array<String>;
	public var typesPack(get, never):Array<String>;
	
	inline function get_pack():Array<String> return ['grest', this.name, this.version];
	inline function get_apiPack():Array<String> return pack.concat(['types']);
	inline function get_typesPack():Array<String> return pack.concat(['api']);
}
