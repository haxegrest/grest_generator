package;

import grest.discovery.Discovery;
import grest.generator.Types;
import tink.unit.Assert.*;

class TypesTest {
	public function new() {}
	
	@:variant("https://www.googleapis.com/discovery/v1/apis/games/v1/rest")
	public function parse(url:String) {
		return Discovery.parseUrl(url)
			.next(Types.generate)
			.next(function(types) {
				trace(types);
				return assert(true);
			});
	}
}