// Squad membership — the only owner of squad state. Every other module
// queries through here and none of them touch player.rsg_squad directly.
//
// A squad is an integer on the player, not an engine concept: that is what
// lets nine of them exist in a gametype that ships with two teams.

#include common_scripts\utility;

// Liveness, our own, because the stock predicate CANNOT be trusted here: it
// returns false for bots that are demonstrably alive (isalive=1,
// sessionstate="playing", and killing each other in the log). Using it would
// make any squad containing a bot read as permanently wiped and eliminated
// instantly. These two conditions are what actually distinguish a player who
// can be shot, and they hold for humans and bots alike.
rsg_is_alive( ent )
{
	if ( !isdefined( ent ) )
		return 0;

	if ( !isalive( ent ) )
		return 0;

	if ( ent.sessionstate != "playing" )
		return 0;

	return 1;
}

init()
{
	// Authoritative roster, keyed by squad id. level.players CANNOT be used
	// for counting at assign time: a player is not in it yet when its
	// "connected" notify fires, so several bots connecting in the same frame
	// all read the same stale count and pile into one squad (observed: five
	// players in a squad of four). Entries are pruned by isdefined, so a
	// disconnect frees its seat without needing a disconnect hook to fire.
	level.rsg.roster = [];

	level thread watch_connects();
}

watch_connects()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread on_connect();
	}
}

on_connect()
{
	self endon( "disconnect" );

	assign( self );
	scripts\mp\_resurgence::rsg_log( "squad: " + self.name + " -> squad " + self.rsg_squad );
	dump_squads();

	self waittill( "disconnect" );

	scripts\mp\_resurgence::rsg_log( "squad: " + self.name + " left squad " + self.rsg_squad );
}

// Fills the lowest-numbered squad with a free slot. Terminates because an id
// beyond every assigned squad always has zero members. A disconnect frees its
// seat automatically, because membership is derived from level.players rather
// than kept in a roster that could drift out of sync.
assign( player )
{
	for ( var_0 = 0; ; var_0++ )
	{
		if ( squad_members( var_0 ).size < level.rsg.squadsize )
		{
			player.rsg_squad = var_0;
			player.rsg_eliminated = 0;

			if ( !isdefined( level.rsg.roster[var_0] ) )
				level.rsg.roster[var_0] = [];

			// Recorded immediately, before the player reaches level.players,
			// so the next assign in this same frame counts it.
			level.rsg.roster[var_0][level.rsg.roster[var_0].size] = player;
			return var_0;
		}
	}
}

squad_of( player )
{
	if ( !isdefined( player ) )
		return undefined;

	return player.rsg_squad;
}

same_squad( a, b )
{
	if ( !isdefined( a ) || !isdefined( b ) )
		return 0;

	if ( a == b )
		return 0;

	if ( !isdefined( a.rsg_squad ) || !isdefined( b.rsg_squad ) )
		return 0;

	return a.rsg_squad == b.rsg_squad;
}

// Reads the roster, not level.players, and prunes entries whose entity is
// gone or has been reassigned.
squad_members( squadid )
{
	var_0 = [];

	if ( !isdefined( level.rsg.roster[squadid] ) )
		return var_0;

	foreach ( var_1 in level.rsg.roster[squadid] )
	{
		if ( !isdefined( var_1 ) || !isplayer( var_1 ) )
			continue;

		if ( !isdefined( var_1.rsg_squad ) || var_1.rsg_squad != squadid )
			continue;

		var_0[var_0.size] = var_1;
	}

	return var_0;
}

squad_living_members( squadid )
{
	var_0 = [];

	foreach ( var_1 in squad_members( squadid ) )
	{
		if ( rsg_is_alive( var_1 ) )
			var_0[var_0.size] = var_1;
	}

	return var_0;
}

// A player sitting out the redeploy delay does NOT count as alive, so if the
// last living member dies while a squadmate waits to redeploy, the squad is
// wiped and that pending redeploy is cancelled.
squad_is_wiped( squadid )
{
	if ( squad_members( squadid ).size == 0 )
		return 0;

	return squad_living_members( squadid ).size == 0;
}

// Squads that currently hold at least one connected player.
squad_ids()
{
	var_0 = [];

	for ( var_1 = 0; var_1 < level.rsg.roster.size; var_1++ )
	{
		if ( squad_members( var_1 ).size > 0 )
			var_0[var_0.size] = var_1;
	}

	return var_0;
}

living_squad_ids()
{
	var_0 = [];

	foreach ( var_1 in squad_ids() )
	{
		if ( squad_living_members( var_1 ).size > 0 )
			var_0[var_0.size] = var_1;
	}

	return var_0;
}

dump_squads()
{
	if ( !isdefined( level.rsg ) || !level.rsg.debug )
		return;

	scripts\mp\_resurgence::rsg_log( "  --- squads: " + squad_ids().size + " squad(s) ---" );

	foreach ( var_0 in squad_ids() )
	{
		var_1 = "";

		foreach ( var_2 in squad_members( var_0 ) )
			var_1 = var_1 + var_2.name + "(" + rsg_is_alive( var_2 ) + ") ";

		scripts\mp\_resurgence::rsg_log( "  squad " + var_0 + " [" + squad_members( var_0 ).size + "/" + level.rsg.squadsize + "]: " + var_1 );
	}
}
