-- Online player-vs-player games.
--
-- Clients never write to the table directly: every change goes through the security definer functions below,
-- which check that the caller is a player in the game and that it is their turn. Players read their own games
-- (and get live updates through Realtime) via the select policy.
--
-- Move legality is checked by both clients with the app's Referee rather than in SQL. The server only enforces
-- turn order, so a modified client could submit a nonsense move; the opponent's client will refuse to apply it.

create table public.online_games (
  id uuid primary key default gen_random_uuid(),
  -- Short code the host shares so a friend can join.
  code text not null unique,
  created_by uuid not null references auth.users (id) on delete cascade,
  white_id uuid references auth.users (id) on delete set null,
  black_id uuid references auth.users (id) on delete set null,
  white_name text check (char_length(white_name) <= 24),
  black_name text check (char_length(black_name) <= 24),
  status text not null default 'waiting' check (status in ('waiting', 'active', 'finished', 'cancelled')),
  -- Every move played so far in UCI notation, from the standard starting position.
  moves text[] not null default '{}',
  result text check (result in ('1-0', '0-1', '1/2-1/2')),
  termination text,
  draw_offered_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index online_games_white_id_idx on public.online_games (white_id);
create index online_games_black_id_idx on public.online_games (black_id);

alter table public.online_games enable row level security;

create policy "Players can read their own games"
  on public.online_games
  for select
  to authenticated
  using ((select auth.uid()) = white_id or (select auth.uid()) = black_id);

-- No insert/update/delete policies: writes only happen through the functions below.

alter publication supabase_realtime add table public.online_games;

-- Creates a game waiting for an opponent. p_side is 'white', 'black' or 'random'.
create function public.create_online_game(p_name text, p_side text default 'random')
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  host_is_white boolean;
  new_code text;
  game public.online_games;
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  host_is_white := case p_side
    when 'white' then true
    when 'black' then false
    when 'random' then random() < 0.5
    else null
  end;
  if host_is_white is null then
    raise exception 'Side must be white, black or random';
  end if;

  loop
    new_code := '';
    for i in 1..6 loop
      new_code := new_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.online_games g where g.code = new_code);
  end loop;

  insert into public.online_games (code, created_by, white_id, black_id, white_name, black_name)
  values (
    new_code,
    uid,
    case when host_is_white then uid end,
    case when host_is_white then null else uid end,
    case when host_is_white then left(p_name, 24) end,
    case when host_is_white then null else left(p_name, 24) end
  )
  returning * into game;

  return game;
end;
$$;

-- Takes the empty seat in a waiting game. Rejoining a game you are already in just returns it.
create function public.join_online_game(p_code text, p_name text)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  select * into game from public.online_games g where g.code = upper(trim(p_code)) for update;
  if not found then
    raise exception 'Game not found';
  end if;

  if uid = game.white_id or uid = game.black_id then
    return game;
  end if;
  if game.status <> 'waiting' then
    raise exception 'Game has already started';
  end if;

  update public.online_games g
  set white_id = coalesce(g.white_id, uid),
      white_name = case when g.white_id is null then left(p_name, 24) else g.white_name end,
      black_id = coalesce(g.black_id, uid),
      black_name = case when g.black_id is null then left(p_name, 24) else g.black_name end,
      status = 'active',
      updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

-- Appends a move. p_ply must equal the number of moves already played so a stale client can't play twice.
-- When the move ends the game the client passes the result and termination along with it.
create function public.play_online_move(
  p_game_id uuid,
  p_uci text,
  p_ply int,
  p_result text default null,
  p_termination text default null
)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  select * into game from public.online_games g where g.id = p_game_id for update;
  if not found or uid is null or uid is distinct from game.white_id and uid is distinct from game.black_id then
    raise exception 'Game not found';
  end if;
  if game.status <> 'active' then
    raise exception 'Game is not in progress';
  end if;
  if p_ply <> cardinality(game.moves) then
    raise exception 'Out of sync: expected ply %, got %', cardinality(game.moves), p_ply;
  end if;
  if (p_ply % 2 = 0 and uid is distinct from game.white_id) or (p_ply % 2 = 1 and uid is distinct from game.black_id) then
    raise exception 'Not your turn';
  end if;
  if p_uci !~ '^[a-h][1-8][a-h][1-8][qrbn]?$' then
    raise exception 'Malformed move %', p_uci;
  end if;
  if p_result is not null and (
    p_result not in ('1-0', '0-1', '1/2-1/2')
    or p_termination is null
    or p_termination not in ('checkmate', 'stalemate', 'threefoldRepetition', 'fiftyMoveRule', 'insufficientMaterial', 'maxMoves')
  ) then
    raise exception 'Invalid result';
  end if;

  update public.online_games g
  set moves = g.moves || p_uci,
      -- Moving instead of answering declines any pending draw offer.
      draw_offered_by = null,
      status = case when p_result is null then 'active' else 'finished' end,
      result = p_result,
      termination = case when p_result is null then null else p_termination end,
      updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

create function public.resign_online_game(p_game_id uuid)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  select * into game from public.online_games g where g.id = p_game_id for update;
  if not found or uid is null or uid is distinct from game.white_id and uid is distinct from game.black_id then
    raise exception 'Game not found';
  end if;
  if game.status <> 'active' then
    raise exception 'Game is not in progress';
  end if;

  update public.online_games g
  set status = 'finished',
      result = case when uid = g.white_id then '0-1' else '1-0' end,
      termination = 'resignation',
      draw_offered_by = null,
      updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

create function public.offer_online_draw(p_game_id uuid)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  select * into game from public.online_games g where g.id = p_game_id for update;
  if not found or uid is null or uid is distinct from game.white_id and uid is distinct from game.black_id then
    raise exception 'Game not found';
  end if;
  if game.status <> 'active' then
    raise exception 'Game is not in progress';
  end if;

  update public.online_games g
  set draw_offered_by = uid, updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

-- Accepts or declines the opponent's pending draw offer.
create function public.answer_online_draw(p_game_id uuid, p_accept boolean)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  select * into game from public.online_games g where g.id = p_game_id for update;
  if not found or uid is null or uid is distinct from game.white_id and uid is distinct from game.black_id then
    raise exception 'Game not found';
  end if;
  if game.status <> 'active' or game.draw_offered_by is null or game.draw_offered_by = uid then
    raise exception 'No draw offer to answer';
  end if;

  update public.online_games g
  set draw_offered_by = null,
      status = case when p_accept then 'finished' else g.status end,
      result = case when p_accept then '1/2-1/2' else g.result end,
      termination = case when p_accept then 'agreement' else g.termination end,
      updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

-- Lets the host abandon a game nobody has joined yet.
create function public.cancel_online_game(p_game_id uuid)
returns public.online_games
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  game public.online_games;
begin
  select * into game from public.online_games g where g.id = p_game_id for update;
  if not found or uid is null or uid is distinct from game.created_by then
    raise exception 'Game not found';
  end if;
  if game.status <> 'waiting' then
    raise exception 'Game has already started';
  end if;

  update public.online_games g
  set status = 'cancelled', updated_at = now()
  where g.id = game.id
  returning * into game;

  return game;
end;
$$;

revoke execute on function
  public.create_online_game(text, text),
  public.join_online_game(text, text),
  public.play_online_move(uuid, text, int, text, text),
  public.resign_online_game(uuid),
  public.offer_online_draw(uuid),
  public.answer_online_draw(uuid, boolean),
  public.cancel_online_game(uuid)
from public, anon;

grant execute on function
  public.create_online_game(text, text),
  public.join_online_game(text, text),
  public.play_online_move(uuid, text, int, text, text),
  public.resign_online_game(uuid),
  public.offer_online_draw(uuid),
  public.answer_online_draw(uuid, boolean),
  public.cancel_online_game(uuid)
to authenticated;
