package grest.generator;

using tink.CoreApi;

class CliCommand {
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
						})
						.mapError(e -> Error.withData(url, e));
				}));
			});
	}
}