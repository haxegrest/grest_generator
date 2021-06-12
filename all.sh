#!/bin/sh

# haxe run.hxml all -o ../grest/src

haxe build-nodejs.hxml
node bin/run.js all -o ../grest/src

# haxe build-jvm.hxml
# java -jar bin/Generator.jar all -o ../grest/src