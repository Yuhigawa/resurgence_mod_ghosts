// Wipes and last squad standing.
//
// Polls rather than hooking a death callback: level.onplayerkilled is called
// at _damage.gsc:852 and dm.gsc assigns it for scoring, so hooking it would
// mean chaining through stock code for no gain. Polling answers the only
// question we actually have -- is anyone in this squad still alive.

init()
{
	level thread watch();
}

watch()
{
	level endon( "game_ended" );

	level waittill( "prematch_over" );

	for (;;)
	{
		wait 0.5;

		if ( game["state"] != "playing" )
			continue;

		// Grace-period deaths do not count. This also neutralises setteam()
		// at _menus.gsc:362, which clears self.hasspawned and then suicides
		// the player: without this a menu team-switch would cost a life
		// before the match had started.
		if ( level.ingraceperiod )
			continue;

		check_wipes();
		check_everyone_dead();
		check_last_squad();
	}
}

check_wipes()
{
	foreach ( var_0 in scripts\mp\resurgence\_squads::squad_ids() )
	{
		if ( !scripts\mp\resurgence\_squads::squad_is_wiped( var_0 ) )
			continue;

		var_1 = scripts\mp\resurgence\_squads::squad_members( var_0 );

		if ( all_eliminated( var_1 ) )
			continue;

		iprintln( squad_names( var_0 ) + " eliminated" );
		scripts\mp\_resurgence::rsg_log( "win: squad " + var_0 + " wiped, eliminating " + var_1.size + " member(s)" );

		foreach ( var_2 in var_1 )
			scripts\mp\resurgence\_redeploy::eliminate( var_2 );
	}
}

// Everyone dead at once -- the ring catching the last two together, or an
// admin killall. living_squad_ids() is then empty, so check_last_squad's
// "exactly one squad alive" test never fires and the match hangs forever.
// Vanilla treats this as a tie (_gamelogic.gsc:116 ends with an undefined
// winner in non-teambased modes).
check_everyone_dead()
{
	var_0 = scripts\mp\resurgence\_squads::squad_ids();

	if ( var_0.size == 0 )
		return;

	if ( scripts\mp\resurgence\_squads::living_squad_ids().size > 0 )
		return;

	// Only when every squad is genuinely wiped, not merely mid-respawn.
	foreach ( var_1 in var_0 )
	{
		if ( !scripts\mp\resurgence\_squads::squad_is_wiped( var_1 ) )
			return;
	}

	iprintlnbold( "EVERYONE IS DEAD - DRAW" );
	scripts\mp\_resurgence::rsg_log( "win: all " + var_0.size + " squad(s) wiped, ending match as a draw" );

	var_2 = game["end_reason"]["tie"];

	if ( !isdefined( var_2 ) )
		var_2 = game["end_reason"]["ended_game"];

	level thread maps\mp\gametypes\_gamelogic::endgame( undefined, var_2 );
}

check_last_squad()
{
	var_0 = scripts\mp\resurgence\_squads::living_squad_ids();

	if ( var_0.size != 1 )
		return;

	// A solo tester is one squad from the start; without this the match would
	// end the instant the grace period expired.
	if ( scripts\mp\resurgence\_squads::squad_ids().size < 2 )
		return;

	var_1 = scripts\mp\resurgence\_squads::squad_living_members( var_0[0] );

	if ( var_1.size == 0 )
		return;

	// Every other squad must actually be out, not merely respawning.
	foreach ( var_2 in scripts\mp\resurgence\_squads::squad_ids() )
	{
		if ( var_2 == var_0[0] )
			continue;

		if ( !scripts\mp\resurgence\_squads::squad_is_wiped( var_2 ) )
			return;
	}

	// "squad 0 wins" means nothing to a player who does not know which squad
	// he is in -- a human won a match and could not tell. Name the winners,
	// and tell them directly.
	iprintlnbold( squad_names( var_0[0] ) + " WINS" );

	foreach ( var_3 in scripts\mp\resurgence\_squads::squad_members( var_0[0] ) )
		var_3 iprintlnbold( "YOU WIN" );

	scripts\mp\_resurgence::rsg_log( "win: squad " + var_0[0] + " is last standing, ending match" );
	scripts\mp\resurgence\_squads::dump_squads();

	// endgame()'s winner is a PLAYER entity in non-teambased modes
	// (_gamelogic.gsc:134 passes one), so pass a living member.
	var_4 = game["end_reason"]["enemies_eliminated"];

	if ( !isdefined( var_4 ) )
		var_4 = game["end_reason"]["ended_game"];

	level thread maps\mp\gametypes\_gamelogic::endgame( var_1[0], var_4 );
}

all_eliminated( members )
{
	foreach ( var_0 in members )
	{
		if ( !isdefined( var_0.rsg_eliminated ) || !var_0.rsg_eliminated )
			return 0;
	}

	return 1;
}

// Readable list of a squad's members, for messages players actually see.
squad_names( squadid )
{
	var_0 = scripts\mp\resurgence\_squads::squad_members( squadid );
	var_1 = "";

	for ( var_2 = 0; var_2 < var_0.size; var_2++ )
	{
		if ( var_2 > 0 )
			var_1 = var_1 + " + ";

		var_1 = var_1 + var_0[var_2].name;
	}

	if ( var_1 == "" )
		var_1 = "squad " + squadid;

	return var_1;
}
