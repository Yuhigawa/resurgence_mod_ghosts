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
	level.rsg.spawnmindist = getdvarint( "scr_resurgence_spawn_min_dist" );
	level.rsg.primary = getdvar( "scr_resurgence_primary" );
	level.rsg.secondary = getdvar( "scr_resurgence_secondary" );

	rsg_log( "init: enabled, squadsize " + level.rsg.squadsize + ", redeploy " + level.rsg.redeploydelay + "s" );

	scripts\mp\resurgence\_squads::init();
	scripts\mp\resurgence\_movement::init();
	scripts\mp\resurgence\_zone::init();
	scripts\mp\resurgence\_win::init();
	if ( !getdvarint( "scr_resurgence_debug_nohooks", 0 ) )
	{
		scripts\mp\resurgence\_redeploy::init();
		scripts\mp\resurgence\_friendlyfire::init();
		scripts\mp\resurgence\_ttk::init();
		scripts\mp\resurgence\_loadout::init();
		scripts\mp\resurgence\_loadout::init_player_watcher();
	}

	install_callbacks();
	level thread reassert_callbacks();
	level thread ensure_vision();
	level thread debug_player_state();
}

register_dvars()
{
	setdvarifuninitialized( "scr_resurgence_enabled", 0 );
	setdvarifuninitialized( "scr_resurgence_squadsize", 2 );
	setdvarifuninitialized( "scr_resurgence_redeploydelay", 15 );
	setdvarifuninitialized( "scr_resurgence_spawn_min_dist", 200 );
	setdvarifuninitialized( "scr_resurgence_speed_scale", 1.02 );
	setdvarifuninitialized( "scr_resurgence_sprint_scale", 1.05 );
	setdvarifuninitialized( "scr_resurgence_damage_scale", 0.7 );
	setdvarifuninitialized( "scr_resurgence_knife_hits", 3 );
	setdvarifuninitialized( "scr_resurgence_primary", "iw6_imbel_mp" );
	setdvarifuninitialized( "scr_resurgence_secondary", "iw6_p226_mp" );
	setdvarifuninitialized( "scr_resurgence_perks", "specialty_lightweight specialty_fastsprintrecovery specialty_unlimitedsprint specialty_marathon specialty_extremeconditioning" );
	setdvarifuninitialized( "scr_resurgence_zone_enabled", 1 );
	setdvarifuninitialized( "scr_resurgence_zone_phases", 5 );
	setdvarifuninitialized( "scr_resurgence_zone_radius_start", 2600 );
	setdvarifuninitialized( "scr_resurgence_zone_radius_end", 250 );
	setdvarifuninitialized( "scr_resurgence_zone_hold", 35 );
	setdvarifuninitialized( "scr_resurgence_zone_shrink", 20 );
	setdvarifuninitialized( "scr_resurgence_zone_damage", 5 );
	setdvarifuninitialized( "scr_resurgence_zone_markers", 0 );
	setdvarifuninitialized( "scr_resurgence_zone_marker_icon", "compassiconfriendly" );
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

	if ( !getdvarint( "scr_resurgence_debug_nohooks", 0 ) )
		scripts\mp\resurgence\_redeploy::install_callbacks();

	scripts\mp\resurgence\_spawning::install_callbacks();
	scripts\mp\resurgence\_loadout::install_callbacks();
	rsg_log( "install_callbacks (pass " + level.rsg.installs + "): onrespawndelay + getspawnpoint set" );
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

// TEMPORARY (Task 5 diagnosis). Separates the three notions of "alive" so we
// can tell whether bots are not spawning at all, or are spawning but failing
// maps\mp\_utility::isreallyalive -- which would silently make every squad
// read as wiped.
debug_player_state()
{
	level endon( "game_ended" );

	for (;;)
	{
		wait 10;

		if ( !getdvarint( "scr_resurgence_debug_state", 0 ) )
			continue;

		foreach ( var_0 in level.players )
		{
			if ( !isdefined( var_0 ) )
				continue;

			rsg_log( "state: " + var_0.name + " isalive=" + isalive( var_0 ) + " sessionstate=" + var_0.sessionstate + " reallyalive=" + var_0 maps\mp\_utility::isreallyalive() + " isai=" + isai( var_0 ) + " isplayer=" + isplayer( var_0 ) );
		}
	}
}

// The map renders pitch black when the match-start sequence is interrupted.
//
// matchstarttimer_internal (_gamelogic.gsc:1091) applies the dark "mpIntro"
// vision set and the clear that follows it (visionsetnaked( "", 3.0 ) at
// :1122) only runs if that function RETURNS. It carries
// level endon( "match_start_timer_beginning" ), and matchstarttimer fires
// that notify on every call, so an interrupted or restarted start sequence
// leaves the intro vision applied forever. Our matches end fast and cycle
// repeatedly, which is exactly that stress -- observed as a fully unlit map
// with working geometry, HUD and minimap.
//
// Clearing it ourselves once play begins is cheap and idempotent.
ensure_vision()
{
	level endon( "game_ended" );

	level waittill( "prematch_over" );

	visionsetnaked( "", 0 );
	rsg_log( "vision: cleared the intro vision set" );
}
