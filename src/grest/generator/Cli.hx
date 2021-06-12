package grest.generator;

class Cli {
	
	static function main() {
		#if nodejs
		var sms = js.Lib.require('source-map-support');
		sms.install();
		haxe.NativeStackTrace.wrapCallSite = sms.wrapCallSite;
		#end
		tink.Cli.process(Sys.args(), new CliCommand()).handle(tink.Cli.exit);
	}
}