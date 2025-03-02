# WebWhisper
A simple whisper mod so your nosy neighbors won't hear your private conversations!



## Usage:

### `/w <username> <message>` | `/whisper <username> <message>`
- Sends a whisper to a player in your lobby.
- If there are usernames in your lobby that are the same with different capitalization, you will have to match their exact capitalization.
- If you run into other problems, you can wrap the username in brackets `[username]` for clarity.


### `/reply` | `/r`
- Autocomplete `/w <username>` for the last person who sent you a whisper.


### `/whisperhelp` | `/whelp` | `/wh` | `/w?` | `/whisper?`
- Displays a list of all WebWhisper commands.


### `/whisperoff` | `/woff`
- Disables receiving whispers, you won't see whispers from other players.


### `/whisperon` | `/won`
- Enables receiving whispers. By default, whispers are enabled.


### `/whispercolor <ARGB hex>` | `/whispercolor <RGB hex>`
- Changes the color of whisper messages in the chat.
- `<ARGB hex>`: A 6-digit RGB code, or 8-digit ARGB hex code with the first two for alpha (transparency).
```
/whispercolor FF00FF00
(set color to green!)
    
/whispercolor DD7C8AB1    
/whispercolor
(both of these set color to default)           
```


### `/sendwhisperformat <format>`
- Changes the format of the receipt shown when you send a whisper.
- `<format>`: A string where `%u` represents the recipient's username and `%m` represents the message.
- **Default**: `<to %u>: %m`
```
/sendwhisperformat [You -> %u]: %m
(make whispers you send appear as "[You -> <their_username>]: Hi this is a sent whisper!")

/sendwhisperformat <you>: %m
(make whispers you send appear as "<you>: Hi this is a sent whisper!")

/sendwhisperformat
(toggle between default and disabled receipts)                 
```


### `/getwhisperformat <format>`
- Changes the format of received whispers.
- `<format>`: A string where `%u` represents the sender's username and `%m` represents the message. 
- This format must include both `%u` and `%m`.
- **Default**: `<whisper from %u>: %m`
```
/getwhisperformat [%u whispers]: %m
(make whispers you get appear as "[<their_username> whispers]: Hi this is a received whisper!")
```


### `/whisperreset` | `/wreset`
- Resets all whisper settings to their default values.


---


### Credits:
Co-author: Zonalic

Thank you [Toes](https://thunderstore.io/c/webfishing/p/toes/) for some great advice! 

If you want to start modding, I found [BlueberryWolf's modding guide](https://github.com/BlueberryWolf/WEBFISHINGModdingGuide) super helpful!


### Ran into a bug?
You can email me at [wndrmeln@gmail.com](mailto:wndrmeln@gmail.com)
