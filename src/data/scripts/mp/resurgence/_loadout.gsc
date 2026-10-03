// Loadout — fixed kit, no class menu.
//
// Resurgence gives everyone the same kit, so the class-selection step should
// not exist. That is also a hard requirement rather than a nicety: a human
// client parks in waitforclassselect() (_menus.gsc:426) on
// waittill( "luinotifyserver" ) until its LUA sends "class_select", and if
// that never arrives the player never spawns and vanilla's kickifdontspawn
// (_playerlogic.gsc:1506) drops them after 90s. Observed on a real client.
//
// Bots are unaffected either way: _menus.gsc:450 handles them through the
// isBot branch, which is why bots spawned fine while a human could not.

init()
{
	// _menus.gsc:434 reads:
	//   if ( allowclasschoice() || showfakeloadout() && !isai( self ) )
	//       wait for the client's selection
	//   else
	//       bypassclasschoice()
	// Precedence is a || (b && c), so BOTH predicates must be false for a
	// human to take the bypass branch. Both live in _utility (a fastfile),
	// so they are replaced rather than edited (ADR-6).
	replacefunc( maps\mp\_utility::allowclasschoice, ::rsg_no_class_choice );
	replacefunc( maps\mp\_utility::showfakeloadout, ::rsg_no_class_choice );
}

install_callbacks()
{
	// Consumed by bypassclasschoice() at _menus.gsc:518-522.
	level.bypassclasschoicefunc = ::rsg_bypassclasschoice;
}

// Applies the kit AFTER the stock loadout has run, instead of replacing it.
//
// The first version replaced _class::giveloadout outright. That skipped
// whatever the stock loadout does besides handing out guns -- including
// assigning the player's character model, which nothing in the spawn path
// does and which aliens.gsc:1132 sets explicitly inside its own loadout
// function. Result: players spawned with no body and were invisible.
// replacefunc offers no way to call the original, so the kit cannot be
// applied from inside that hook at all.
//
// Instead, each player runs a watcher that waits for its own spawn, lets the
// stock loadout complete, and then strips and re-arms. One frame of the
// class weapon is the price of keeping the model.
init_player_watcher()
{
	level thread watch_spawns();
}

watch_spawns()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread kit_on_spawn();
	}
}

kit_on_spawn()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "spawned_player" );

		// Let spawnplayer finish: _class::setclass at :694 and
		// _class::giveloadout at :696 both run after the "spawned" notify.
		wait 0.1;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			continue;

		// Restore this player's base vision set on every spawn. The global
		// clear in _resurgence::ensure_vision covers players present when
		// play begins; this covers everyone else, including anyone who
		// joins mid-match after the clear has already happened.
		self maps\mp\_utility::restorebasevisionset( 0 );

		apply_kit();
	}
}

apply_kit()
{
	// Killstreaks must go after the stock loadout granted them.
	self.killstreaktype = "none";
	maps\mp\_utility::_setactionslot( 4, "" );

	if ( level.rsg.primary == "" )
	{
		scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " killstreaks stripped, class kit kept" );
		return;
	}

	self takeallweapons();
	self giveweapon( level.rsg.primary );
	self setspawnweapon( level.rsg.primary );

	if ( level.rsg.secondary != "" )
		self giveweapon( level.rsg.secondary );

	self switchtoweapon( level.rsg.primary );
	scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " kit " + level.rsg.primary + " / " + level.rsg.secondary );
}

// Both predicates in _menus.gsc:434 must be false for a human to take the
// bypassclasschoice() branch, since precedence there is a || (b && c).
rsg_no_class_choice()
{
	return 0;
}

// Consumed by bypassclasschoice() at _menus.gsc:518-522.
rsg_bypassclasschoice()
{
	return "class0";
}
