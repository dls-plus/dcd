#!/usr/bin/env rdmd

static immutable helpString = q"[Helper script test_with_package.d
Usage:
  VERSION=<min/max/both> PACKAGE=<name> rdmd test_with_package.d [-- command...]
  VERSION=<min/max/both> rdmd test_with_package.d <package> [-- command...]
  rdmd test_with_package.d <min/max/both> <package> [-- command...]

Runs `dub test --compiler=$DC` with either the minimum available version on DUB
or the maximum available version on dub, respecting the dub.json version range.

Running with VERSION=min will use the lowest available version of a package,
for a version specification of format
  "~>0.13.0" this will run with "0.13.0",
  ">=0.13.0" this will run with "0.13.0",
  ">=0.13.0 <0.15.0" this will run with "0.13.0"
  otherwise error.

Running with VERSION=max will use the highest available version of a package,
for a version specification of format
  "~>0.13.0" this will run with "~>0.13.0",
  ">=0.13.0" this will run with ">=0.13.0",
  ">=0.13.0 <0.15.0" this will run with "<0.15.0"
  otherwise error.

Running with VERSION=both will run this script first with max, then with min.
This is also the default mode when no VERSION is specified. For CI it may be
better to explicitly state this for parallelism and cleaner test logs though.

To specify a version, either set the VERSION environment variable or pass in the
version (min/max/both) as first argument before the package name.

Running this script either expects a package name as only or as second argument
or if no arguments are given, through the PACKAGE environment variable.

Temporarily creates a dub.json file and renames the original to dub.<n>.json,
both of which is undone automatically on exit.

`dub upgrade` will be run after creating the artificial dub.json and before
running the test command. It might be necessary to call `dub upgrade` manually
again after the test commands are finished to restore the dependencies back to
the newest versions.

If you run with `-- <command>` then that command will be run instead of
`dub test --compiler=$DC`

The script returns 0 on success after all commands or 1 if anything fails. If
`both` is specified as version and both commands fail, this returns 2.
]";

import std;
import fs = std.file;

int main(string[] args)
{
	/// wanted target version (min, max or both)
	string ver = environment.get("VERSION", "both");
	/// package to modify and test
	string pkg = environment.get("PACKAGE", "");
	/// D compiler to use
	const dc = environment.get("DC", "dmd");

	auto cmd = ["dub", "test", "--compiler=" ~ dc];
	auto cmdIndex = args.countUntil("--");
	if (cmdIndex != -1)
	{
		cmd = args[cmdIndex + 1 .. $];
		args = args[0 .. cmdIndex];
	}

	if (args.any!(among!("-h", "-help", "--help")))
	{
		stderr.writeln(helpString);
		return 0;
	}

	if (args.length == 2)
	{
		// <program> <package>
		pkg = args[1];
	}
	else if (args.length == 3)
	{
		// <program> <version> <package>
		ver = args[1];
		pkg = args[2];
	}

	if (!pkg.length)
	{
		stderr.writefln("No package specified. Try --help?");
		return 1;
	}

	if (ver == "both")
	{
		int result = 0;
		result += doRun("max", pkg, dc, cmd);
		stderr.writeln();
		result += doRun("min", pkg, dc, cmd);
		return result;
	}
	else
	{
		return doRun(ver, pkg, dc, cmd);
	}
}

int doRun(string ver, string pkg, string dc, string[] cmd)
{
	if (!ver.among!("min", "max"))
	{
		stderr.writefln("Unsupported version '%s', try min, max or both instead",
			ver);
		return 1;
	}

	stderr.writefln("(PACKAGE=%s, VERSION=%s, DC=%s)", pkg, ver, dc);

	if (!exists("dub.json"))
	{
		stderr.writefln("No dub.json file exists in the current working "
			~ "directory '%s'! dub.sdl files are not supported.", getcwd());
		return 1;
	}

	auto json = parseJSON(readText("dub.json"));
	if ("dependencies" !in json || pkg !in json["dependencies"])
	{
		stderr.writefln("dub.json doesn't specify '%s' as dependency.", pkg);
		return 1;
	}
	auto verSpec = json["dependencies"][pkg];
	if (verSpec.type != JSONType.string)
	{
		stderr.writefln("Unsupported dub.json version '%s' (should be string)",
			verSpec);
		return 1;
	}

	// find the version range to use based on the dependency version and wanted
	// version target.
	string determined = resolveVersion(verSpec.str, ver);
	stderr.writefln("Testing using %s version %s.", pkg, determined);

	json["dependencies"][pkg] = JSONValue(determined);

	// backup dub.json to dub.<n>.json and restore on exit
	string tmpDubName;
	for (int n = 1;; n++)
	{
		// lots of GC alloc but it doesn't matter for a script like this
		tmpDubName = "dub." ~ n.to!string ~ ".json";
		if (!exists(tmpDubName))
			break;
	}
	fs.rename("dub.json", tmpDubName);
	scope (exit)
		fs.rename(tmpDubName, "dub.json");

	// create dummy dub.json and delete on exit
	fs.write("dub.json", json.toPrettyString);
	scope (exit)
		fs.remove("dub.json");

	stderr.writeln("$ dub upgrade");
	if (spawnShell("dub upgrade").wait != 0)
		return 1;

	stderr.writefln("$ %(%s %)", cmd);
	if (spawnProcess(cmd).wait != 0)
		return 1;

	return 0;
}

string resolveVersion(string verRange, string wanted)
{
	if (verRange.startsWith("~>"))
	{
		switch (wanted)
		{
		case "min":
			return verRange[2 .. $];
		case "max":
			return verRange;
		default:
			assert(false, "unknown target version " ~ wanted);
		}
	}
	else if (verRange.startsWith(">="))
	{
		auto end = verRange.indexOf("<");
		if (end == -1)
		{
			switch (wanted)
			{
			case "min":
				return verRange[2 .. $];
			case "max":
				return verRange;
			default:
				assert(false, "unknown target version " ~ wanted);
			}
		}
		else
		{
			switch (wanted)
			{
			case "min":
				return verRange[2 .. end].strip;
			case "max":
				return verRange[end .. $];
			default:
				assert(false, "unknown target version " ~ wanted);
			}
		}
	}
	else
		throw new Exception("Unsupported version range specifier to multi-test: "
			~ verRange);
}
