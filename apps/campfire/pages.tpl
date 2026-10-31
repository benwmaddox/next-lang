// The pages of the Campfire app. Each can write at most the size in its header, worked out when the program is built.
html template text(message: Ascii max 32) max 196608
{message}
html template home(user: User, rooms: list<Room, 100>) max 196608
<!doctype html><html><head><meta charset="utf-8"><title>Campfire</title></head><body><nav id="sidebar"><h1>{user.name}</h1><ul>{#for r in rooms}<li><a href="/rooms/{r.id}">{r.name}</a></li>{#end}</ul></nav></body></html>
html template room(user: User, room: Room, rooms: list<Room, 100>, messages: list<Message, 40>) max 196608
<!doctype html><html><head><meta charset="utf-8"><title>{room.name} - Campfire</title></head><body><nav id="sidebar"><h1>{user.name}</h1><ul>{#for r in rooms}<li><a href="/rooms/{r.id}">{r.name}</a></li>{#end}</ul></nav><main id="room" data-room-id="{room.id}"><header><h2>{room.name}</h2></header><div id="messages">{#for m in messages}<div class="message" id="message_{m.client_message_id}" data-message-id="{m.id}" data-user-id="{m.creator_id}"><strong class="message__author">{m.author}</strong> <time class="message__time">{m.created_at}</time><div id="presentation_message_{m.id}" class="message__body">{m.body|raw}</div></div>{#end}</div></main></body></html>
html template signin(failed: bool) max 196608
<!doctype html><html><head><meta charset="utf-8"><title>Sign in - Campfire</title></head><body><main id="sign-in">{#if failed}<p class="flash">Try another email address or password.</p>{#end}<form action="/session" method="post"><input type="email" name="email_address" required autofocus><input type="password" name="password" required><button type="submit">Sign in</button></form></main></body></html>
