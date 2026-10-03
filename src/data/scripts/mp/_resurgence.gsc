// Resurgence — entry point. Registers dvars, builds level.rsg, wires the
// modules, and nothing else. No gameplay logic lives here.
//
// Constraints established by live testing on this build:
//
//   1. The loader enters BOTH main() and init() on the same file, so this
//      file defines init() ONLY. Adding main() would wire everything twice.
//   2. This runs BEFORE the gametype initialises level state. Reading
//      level.teambased or level.gametype here is a script error, not a
//      value, so nothing in init() may touch gametype state.
//   3. init() re-runs on map_restart, so setup is idempotent.
//   4. CBServers RESTORES any file it ships, within ~3s of launch. We may add
//      files to data/ but never modify existing ones, so the gametype's
//      callback overwrite is handled by a thread here (reassert_callbacks)
//      rather than by patching _gamelogic.gsc.
//   5. max() comes from common_scripts\utility, not the engine -- without the
//      include below, init() dies silently at the squadsize line.
//
// Debug output goes through rsg_log, which uses logprint: logstring and
// println write nothing to logs/games_mp.log on this build.

#include common_scripts\utility;

init()
{
	register_dvars();

	if ( !getdvarint( "scr_resurgence_enabled" ) )
		return;

	level.rsg = spawnstruct();
	level.rsg.debug = getdvarint( "scr_resurgence_debug" );
	level.rsg.installs = 0;
	level.rsg.squadsize = max( 1, getdvarint( "scr_resurgence_squadsize" ) );
	level.rsg.redeploydelay = getdvarint( "scr_resurgence_redeploydelay" );
	level.rsg.primary = getdvar( "scr_resurgence_primary" );
	level.rsg.secondary = getdvar( "scr_resurgence_secondary" );

	rsg_log( "init: enabled, squadsize " + level.rsg.squadsize + ", redeploy " + level.rsg.redeploydelay + "s" );

	scripts\mp\resurgence\_squads::init();

	install_callbacks();
	level thread reassert_callbacks();
}

register_dvars()
{
	setdvarifuninitialized( "scr_resurgence_enabled", 0 );
	setdvarifuninitialized( "scr_resurgence_squadsize", 2 );
	setdvarifuninitialized( "scr_resurgence_redeploydelay", 15 );
	setdvarifuninitialized( "scr_resurgence_primary", "" );
	setdvarifuninitialized( "scr_resurgence_secondary", "" );
	setdvarifuninitialized( "scr_resurgence_zone_enabled", 1 );
	setdvarifuninitialized( "scr_resurgence_zone_phases", 5 );
	setdvarifuninitialized( "scr_resurgence_zone_radius_start", 4000 );
	setdvarifuninitialized( "scr_resurgence_zone_radius_end", 400 );
	setdvarifuninitialized( "scr_resurgence_zone_hold", 45 );
	setdvarifuninitialized( "scr_resurgence_zone_shrink", 30 );
	setdvarifuninitialized( "scr_resurgence_zone_damage", 5 );
	setdvarifuninitialized( "scr_resurgence_debug", 0 );
}

// The gametype assigns level.getspawnpoint / onspawnplayer / onrespawndelay
// from inside [[ level.onstartgametype ]](), which runs in the same frame as
// our init() but after it: our scripts are loaded by _load::main() at the top
// of callback_startgametype, and onstartgametype is called further down that
// same function. So whatever init() assigns has been overwritten before the
// frame ends.
//
// Patching _gamelogic.gsc to call us back is not an option -- CBServers
// restores that file. Instead, yield once so we resume on the next frame,
// after the whole synchronous body of callback_startgametype, and install
// again. That second pass is the one that sticks.
reassert_callbacks()
{
	level endon( "game_ended" );

	wait 0.05;
	install_callbacks();

	// Belt and braces: if anything reassigns these later (a round switch, or
	// a gametype doing its own deferred setup), override it once more at the
	// point play actually begins.
	level waittill( "prematch_over" );
	install_callbacks();
}

install_callbacks()
{
	if ( !rsg_on() )
		return;

	level.rsg.installs++;
	rsg_log( "install_callbacks (pass " + level.rsg.installs + ")" );
}

rsg_on()
{
	return isdefined( level.rsg );
}

// logprint is the only one of logstring/println/logprint that reaches
// logs/games_mp.log on this build, and it does not append a newline.
rsg_log( msg )
{
	if ( !isdefined( level.rsg ) || !level.rsg.debug )
		return;

	logprint( "RSG: " + msg + "\n" );
}
