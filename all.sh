#!/bin/sh

# haxe run.hxml all -o temp

haxe build-nodejs.hxml
node bin/run.js all -o temp

# haxe build-jvm.hxml
# java -jar bin/Generator.jar all -o temp