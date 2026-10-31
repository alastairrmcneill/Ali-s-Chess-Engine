# Online player vs player

Two people can play each other over the internet. One creates a game and shares a six-character code, the
other enters it to join. Moves sync live through Supabase.

## How it works

- **Auth**: players are signed in with Supabase anonymous sign-in the first time they open the online lobby.
  The session is kept on the device, so you can leave and come back to a game (it's listed under "Your games",
  or join again with the same code).
- **Table**: `public.online_games` holds one row per game: the two players, status
  (`waiting`/`active`/`finished`/`cancelled`), every move as UCI, the result and any pending draw offer.
- **Writes**: clients can't write to the table. Everything goes through `security definer` functions
  (`create_online_game`, `join_online_game`, `play_online_move`, `resign_online_game`, `offer_online_draw`,
  `answer_online_draw`, `cancel_online_game`) which check the caller is in the game and it's their turn.
  `play_online_move` takes the ply number so a stale client can't move twice.
- **Reads**: RLS lets a player read only their own games. The app subscribes to Realtime `postgres_changes`
  on its game row, and refetches whenever the channel (re)connects.
- **Rules**: legality is checked on both devices with the app's `Referee`, not in SQL. The server enforces
  turn order only, so a modified client could send a bad move or claim a false checkmate; the opponent's app
  refuses illegal moves. Fine for friendly games, but move validation would need to move server side (e.g. an
  Edge Function) before anything ranked.

Not included yet: clocks / time controls, matchmaking with strangers, rematch, abandoned-game cleanup.

## Setup

1. Apply the migration in `supabase/migrations/20261031000000_online_games.sql`
   (`supabase db push`, or paste it into the SQL editor).
2. In the Supabase dashboard enable **Authentication → Sign In / Providers → Allow anonymous sign-ins**.
3. Run the app with the project URL and publishable key:

   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```

   Without these the app works as before and the online lobby explains that online play isn't configured.
