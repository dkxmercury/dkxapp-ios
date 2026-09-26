import Foundation

let dkxStringsTable: [String: [String: String]] = {
    guard let data = dkxStringsJSON.data(using: .utf8), let table = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
        return [:]
    }
    return table
}()

// JSON строкой, а не литералом словаря, потому что словарь на тысячи строк Swift компилирует очень долго
private let dkxStringsJSON = #"""
{
 "\n\nУзбекский iOS пока не распознаёт, поэтому его нет в списке.": {
  "en": "\n\niOS doesn't recognize Uzbek yet, so it's not in the list."
 },
 "\n    (изменено, прежние версии": {
  "en": "\n    (edited, previous versions"
 },
 "\n    (удалено {})": {
  "en": "\n    (deleted {})"
 },
 " · правок {}": {
  "en": " · edits {}"
 },
 " и ": {
  "en": " and "
 },
 "%.1f ГБ": {
  "en": "%.1f GB"
 },
 "%.1f км": {
  "en": "%.1f km"
 },
 "'сегодня в' H:mm": {
  "en": "'today at' H:mm"
 },
 "(переслано от {})": {
  "en": "(forwarded from {})"
 },
 ", дорогу не нашли, едем прямо": {
  "en": ", no road found, going straight"
 },
 ", объём около {}": {
  "en": ", about {}"
 },
 ", прокладываю по дорогам": {
  "en": ", routing along roads"
 },
 ". Нажатие на поле копирует его.": {
  "en": ". Tap a field to copy it."
 },
 ". Это предел за один раз, остальное выгрузите следующим заходом": {
  "en": ". This is the limit for one run, upload the rest next time"
 },
 "30 дней": {
  "en": "30 days"
 },
 "7 дней": {
  "en": "7 days"
 },
 "Client ID не задан в сборке. Выгрузка недоступна.": {
  "en": "Client ID is not set in the build. Upload is unavailable."
 },
 "Face ID на отдельные чаты": {
  "en": "Face ID for individual chats"
 },
 "GEMINI, ДЛЯ УЗБЕКСКОГО": {
  "en": "GEMINI, FOR UZBEK"
 },
 "GLM, ДЛЯ РУССКОГО И АНГЛИЙСКОГО": {
  "en": "GLM, FOR RUSSIAN AND ENGLISH"
 },
 "Google Drive не подключён": {
  "en": "Google Drive is not connected"
 },
 "Google Drive, файлов {}": {
  "en": "Google Drive, {} files"
 },
 "Google не принял загрузку": {
  "en": "Google rejected the upload"
 },
 "Google ответил кодом {}": {
  "en": "Google responded with code {}"
 },
 "ID скопирован": {
  "en": "ID copied"
 },
 "Telegram ID в профиле": {
  "en": "Telegram ID in profile"
 },
 "Telegram для бизнеса": {
  "en": "Telegram Business"
 },
 "[аудио]": {
  "en": "[audio]"
 },
 "[видео]": {
  "en": "[video]"
 },
 "[геопозиция {}, {}]": {
  "en": "[location {}, {}]"
 },
 "[голосовое]": {
  "en": "[voice message]"
 },
 "[контакт {} {} {}]": {
  "en": "[contact {} {} {}]"
 },
 "[кружок]": {
  "en": "[video message]"
 },
 "[опрос]": {
  "en": "[poll]"
 },
 "[пусто]": {
  "en": "[empty]"
 },
 "[служебное]": {
  "en": "[service message]"
 },
 "[стикер]": {
  "en": "[sticker]"
 },
 "[файл {}]": {
  "en": "[file {}]"
 },
 "[фото]": {
  "en": "[photo]"
 },
 "d MMMM 'в' H:mm": {
  "en": "MMMM d 'at' H:mm"
 },
 "iOS при каждой смене значка показывает окно, что значок изменён.\n\nВ Telegram свой выбор значка в «Оформлении» остался как был. Новые картинки добавляются в сборку, с телефона их не поставить.": {
  "en": "iOS shows an alert every time the icon changes.\n\nTelegram's own icon picker in “Appearance” stays as it was. New images are added in the build, they can't be installed from the phone."
 },
 "{} МБ": {
  "en": "{} MB"
 },
 "{} дело|{} дела|{} дел": {
  "en": "{} task|{} tasks"
 },
 "{} дн": {
  "en": "{} d"
 },
 "{} и ещё {}": {
  "en": "{} and {} more"
 },
 "{} км/ч": {
  "en": "{} km/h"
 },
 "{} м": {
  "en": "{} m"
 },
 "{} мин": {
  "en": "{} min"
 },
 "{} просрочено": {
  "en": "{} overdue"
 },
 "{} сегодня": {
  "en": "{} today"
 },
 "{} ч": {
  "en": "{} h"
 },
 "{}: скопировано": {
  "en": "{} copied"
 },
 "«{}» снимется со всех чатов.": {
  "en": "“{}” will be removed from all chats."
 },
 "«Мои дела» в настройках": {
  "en": "“My Tasks” in settings"
 },
 "«Напомнить позже» у чатов и сообщений": {
  "en": "“Remind me later” for chats and messages"
 },
 "«Пароли» в настройках": {
  "en": "“Passwords” in settings"
 },
 "А": {
  "en": "A"
 },
 "Аккаунт": {
  "en": "Account"
 },
 "Английский": {
  "en": "English"
 },
 "Аудио": {
  "en": "Audio"
 },
 "Б": {
  "en": "B"
 },
 "БЕЗ ОТВЕТА": {
  "en": "UNANSWERED"
 },
 "Без Premium кнопки расшифровки не будет.": {
  "en": "Without Premium there will be no transcription button."
 },
 "Без даты": {
  "en": "No date"
 },
 "Без названия": {
  "en": "Untitled"
 },
 "Без напоминания": {
  "en": "No reminder"
 },
 "Без ответа": {
  "en": "Unanswered"
 },
 "Без смайликов": {
  "en": "No emoji"
 },
 "Бирюзовый": {
  "en": "Turquoise"
 },
 "В Google Drive": {
  "en": "Save to Google Drive"
 },
 "В буфере нет текста.": {
  "en": "The clipboard has no text."
 },
 "В момент дела": {
  "en": "At time of task"
 },
 "В пути, {} из {}{}": {
  "en": "On the way, {} of {}{}"
 },
 "В чате шаблоны открываются кнопкой в поле ввода, рядом со стикерами. Выбранный текст вставляется туда, где стоит курсор, и его можно дописать перед отправкой. Порядок в меню тот же, что здесь.": {
  "en": "In a chat, templates open from the button in the input field, next to stickers. The chosen text is inserted at the cursor and can be edited before sending. The menu order is the same as here."
 },
 "ВКЛАДКИ ВНИЗУ": {
  "en": "BOTTOM TABS"
 },
 "Вежливый отказ": {
  "en": "Polite refusal"
 },
 "Вернуть в работу": {
  "en": "Reopen"
 },
 "Весь день": {
  "en": "All day"
 },
 "Видео": {
  "en": "Video"
 },
 "Включите Google Drive в настройках Dkx и войдите в Google.": {
  "en": "Turn on Google Drive in Dkx settings and sign in to Google."
 },
 "Включённый тумблер прячет строку. Вкладки «Чаты» и «Настройки» и строка Dkx не прячутся, иначе спрятанное было бы не вернуть. Строки, которых у вас и так нет, например Прокси без настроенного прокси, не появятся и при выключенном тумблере.": {
  "en": "A switch that is on hides the row. The “Chats” and “Settings” tabs and the Dkx row can't be hidden, otherwise there would be no way back. Rows you don't have anyway, such as Proxy without a configured proxy, won't appear even with the switch off."
 },
 "Войдите в свой Google-аккаунт, чтобы выгружать медиа на Google Drive.": {
  "en": "Sign in to your Google account to upload media to Google Drive."
 },
 "Войти в Google": {
  "en": "Sign in to Google"
 },
 "Все сообщения автора": {
  "en": "All messages from author"
 },
 "Все сообщения автора в группе": {
  "en": "All author's messages in groups"
 },
 "Все, кто писал последним, уже получили ответ. Порог ожидания настраивается в настройках Dkx.": {
  "en": "Everyone who wrote last has already got a reply. The waiting threshold is set in Dkx settings."
 },
 "Вставить из буфера": {
  "en": "Paste from clipboard"
 },
 "Вставьте ключ": {
  "en": "Paste the key"
 },
 "Всё время": {
  "en": "All time"
 },
 "Всё это уже было в Google Drive": {
  "en": "All of this was already on Google Drive"
 },
 "Вы в контактах собеседника": {
  "en": "You are in their contacts"
 },
 "Выбрать дату и время": {
  "en": "Choose date and time"
 },
 "Выгружено {}": {
  "en": "Exported {}"
 },
 "Выгрузить": {
  "en": "Upload"
 },
 "Выгрузить на Google Drive?": {
  "en": "Upload to Google Drive?"
 },
 "Выгрузить чат в файл": {
  "en": "Export chat to file"
 },
 "Выгрузка в Google Drive": {
  "en": "Upload to Google Drive"
 },
 "Выгрузка упёрлась в предел, самые старые сообщения могли не попасть.": {
  "en": "The export hit the limit, the oldest messages may be missing."
 },
 "Выгрузка чата в файл": {
  "en": "Chat export to file"
 },
 "Выключить Face ID на чатах": {
  "en": "Turn off Face ID for chats"
 },
 "Выполнено": {
  "en": "Done"
 },
 "ГЕОПОЗИЦИЯ": {
  "en": "LOCATION"
 },
 "ГЛАВНЫЙ ЭКРАН НАСТРОЕК": {
  "en": "MAIN SETTINGS SCREEN"
 },
 "ГОТОВЫЙ ВАРИАНТ": {
  "en": "RESULT"
 },
 "Геопозиция": {
  "en": "Location"
 },
 "Голосовое": {
  "en": "Voice message"
 },
 "Голосовые и кружки": {
  "en": "Voice and video messages"
 },
 "Готовлю {}": {
  "en": "Preparing {}"
 },
 "Группа": {
  "en": "Group"
 },
 "Данные и память": {
  "en": "Data and Storage"
 },
 "Дата": {
  "en": "Date"
 },
 "Дата и время": {
  "en": "Date and time"
 },
 "Дел пока нет. Нажмите плюс вверху, чтобы добавить первое.": {
  "en": "No tasks yet. Tap plus at the top to add the first one."
 },
 "Дело": {
  "en": "Task"
 },
 "Деловой": {
  "en": "Business"
 },
 "День": {
  "en": "Day"
 },
 "День по часам": {
  "en": "Day by hour"
 },
 "Добавить уместные": {
  "en": "Add fitting ones"
 },
 "Добавить шаблон": {
  "en": "Add template"
 },
 "Долгое нажатие на карту ставит точку": {
  "en": "Long-press the map to set a point"
 },
 "Долгое нажатие на карту ставит точку А": {
  "en": "Long-press the map to set point A"
 },
 "Долгое нажатие переставит Б": {
  "en": "Long-press to move B"
 },
 "Дружелюбный": {
  "en": "Friendly"
 },
 "Думаю…": {
  "en": "Thinking…"
 },
 "Ещё вариант": {
  "en": "Another version"
 },
 "ЖДУТ ОТВЕТА {}": {
  "en": "AWAITING REPLY {}"
 },
 "Ждёт больше 3 часов": {
  "en": "Waiting over 3 hours"
 },
 "Ждёт больше суток": {
  "en": "Waiting over a day"
 },
 "Ждёт больше часа": {
  "en": "Waiting over an hour"
 },
 "Журнал Dkx": {
  "en": "Dkx log"
 },
 "ЗАМЕТКА": {
  "en": "NOTE"
 },
 "За 2 часа": {
  "en": "2 hours before"
 },
 "За день": {
  "en": "1 day before"
 },
 "За час": {
  "en": "1 hour before"
 },
 "За этот период в чате нет медиа выбранных типов.": {
  "en": "The chat has no media of the selected types for this period."
 },
 "Завершить": {
  "en": "Complete"
 },
 "Завершить дело": {
  "en": "Complete task"
 },
 "Завершить дело?": {
  "en": "Complete task?"
 },
 "Завтра": {
  "en": "Tomorrow"
 },
 "Завтра в 9:00": {
  "en": "Tomorrow at 9:00"
 },
 "Загружено в Google Drive": {
  "en": "Uploaded to Google Drive"
 },
 "Загружено в Google Drive, файлов {}": {
  "en": "{} files uploaded to Google Drive"
 },
 "Закрепить у себя": {
  "en": "Pin locally"
 },
 "Закреплён": {
  "en": "Pinned"
 },
 "Закрыть Face ID": {
  "en": "Lock with Face ID"
 },
 "Заменить": {
  "en": "Replace"
 },
 "Заметка в шапке чата": {
  "en": "Note in chat header"
 },
 "Заметка, необязательно": {
  "en": "Note, optional"
 },
 "Заново": {
  "en": "Reset"
 },
 "Записей {}. Хранятся в Keychain только на этом телефоне и не уходят ни на сервер Telegram, ни в iCloud.": {
  "en": "{} saved. Stored in Keychain on this phone only and never sent to Telegram's server or iCloud."
 },
 "Записей пока нет. Все поля необязательны, но хотя бы одно нужно заполнить.": {
  "en": "No entries yet. All fields are optional, but at least one must be filled in."
 },
 "Запись": {
  "en": "Entry"
 },
 "Запись хранится в Keychain только на этом телефоне.": {
  "en": "The entry is stored in Keychain on this phone only."
 },
 "Заполните хотя бы одно поле, иначе сохранять нечего.": {
  "en": "Fill in at least one field, otherwise there's nothing to save."
 },
 "Звонки": {
  "en": "Calls"
 },
 "Звёзды": {
  "en": "Stars"
 },
 "Здесь появится улучшенный текст": {
  "en": "The improved text will appear here"
 },
 "Зелёный": {
  "en": "Green"
 },
 "Значок приложения": {
  "en": "App icon"
 },
 "ИНТЕРФЕЙС": {
  "en": "INTERFACE"
 },
 "Избранное": {
  "en": "Saved Messages"
 },
 "Изменено ": {
  "en": "Updated "
 },
 "Изменить": {
  "en": "Edit"
 },
 "Изменённое": {
  "en": "Edited"
 },
 "Изменённых сообщений нет. Прежние версии сохраняются при включённой «Истории правок».": {
  "en": "No edited messages. Previous versions are saved while “Save edit history” is on."
 },
 "Исправить ошибки": {
  "en": "Fix mistakes"
 },
 "История правок": {
  "en": "Edit history"
 },
 "Ищу в личном чате и общих группах…": {
  "en": "Searching the private chat and common groups…"
 },
 "Ищу…": {
  "en": "Searching…"
 },
 "КОГДА": {
  "en": "WHEN"
 },
 "КОНТАКТЫ И ЧАТЫ": {
  "en": "CONTACTS AND CHATS"
 },
 "Как в тексте": {
  "en": "As in text"
 },
 "Ключ в Google AI Studio, раздел Get API key.": {
  "en": "Get the key in Google AI Studio, Get API key section."
 },
 "Ключ на z.ai, раздел API Keys. Бесплатные модели GLM Flash.": {
  "en": "Get the key at z.ai, API Keys section. Free GLM Flash models."
 },
 "Ключ не сохранён, {}.": {
  "en": "Key not saved, {}."
 },
 "Ключ работает и сохранён.": {
  "en": "The key works and is saved."
 },
 "Ключ удалён.": {
  "en": "Key deleted."
 },
 "Ключа нет": {
  "en": "No key"
 },
 "Ключи": {
  "en": "Keys"
 },
 "Ключи Gemini и GLM": {
  "en": "Gemini and GLM keys"
 },
 "Кнопка в поле ввода": {
  "en": "Button in input field"
 },
 "Кнопка расшифровки появляется у голосовых и кружков. Есть Premium, расшифровывает Telegram. Нет Premium, расшифровывает сам телефон на выбранном языке, на сервер Telegram ничего не уходит. Если язык не скачан на телефон, iOS распознаёт через серверы Apple.": {
  "en": "The transcription button appears on voice and video messages. With Premium, Telegram transcribes. Without Premium, the phone itself transcribes in the selected language, nothing is sent to Telegram's server. If the language isn't downloaded to the phone, iOS recognizes speech via Apple's servers."
 },
 "Кнопка с волшебной палочкой появляется в поле ввода, когда там есть текст. Стиль, смайлики, обращение и язык выбираются на её экране, последний выбор запоминается. Ключи хранятся в Keychain этого телефона и переживают переустановку приложения. Сегодня запросов {}.": {
  "en": "The magic wand button appears in the input field when it has text. Style, emoji, form of address and language are chosen on its screen, the last choice is remembered. Keys are stored in this phone's Keychain and survive reinstalling the app. Requests today {}."
 },
 "Кнопки «Улучшить текст» в поле ввода не будет.": {
  "en": "There will be no “Improve text” button in the input field."
 },
 "Кнопки фото, статуса и имени пользователя": {
  "en": "Photo, status and username buttons"
 },
 "Контакт": {
  "en": "Contact"
 },
 "Контакты": {
  "en": "Contacts"
 },
 "Конфиденциальность": {
  "en": "Privacy and Security"
 },
 "Короче": {
  "en": "Shorter"
 },
 "Красный": {
  "en": "Red"
 },
 "Кружок": {
  "en": "Video message"
 },
 "Лента": {
  "en": "Feed"
 },
 "Лента дел": {
  "en": "Task feed"
 },
 "Лента историй над списком чатов исчезнет полностью. Сами истории останутся доступны в профилях.\n\nБез навязывания пропадут плашки и экраны покупки Premium, пункты Premium, Business и подарков в настройках, значки подарков в поле ввода, а при наборе будут предлагаться только ваши стикеры, без чужих паков. Если Premium уже есть, он продолжит работать. Покупка Stars остаётся. Применяется при следующем открытии экрана.": {
  "en": "The stories bar above the chat list disappears completely. Stories themselves stay available in profiles.\n\nWithout upsells, Premium banners and purchase screens disappear, as do the Premium, Business and gift rows in settings and the gift icons in the input field, and while typing only your own stickers are suggested, without other packs. If you already have Premium, it keeps working. Buying Stars remains. Applies the next time the screen opens."
 },
 "Личные чаты, где последним написал собеседник, без ботов и архива. Сверху те, кто ждёт дольше всех. Ответили, и человек пропадёт из списка сам.": {
  "en": "Private chats where the other person wrote last, without bots and the archive. Those waiting longest are at the top. Once you reply, the person disappears from the list."
 },
 "Личный чат": {
  "en": "Private chat"
 },
 "Логин": {
  "en": "Login"
 },
 "Логин скопирован": {
  "en": "Login copied"
 },
 "МЕТКИ": {
  "en": "LABELS"
 },
 "Маршрут": {
  "en": "Route"
 },
 "Маршрут {}{}. Метки можно перетащить, движение начнётся с трансляцией": {
  "en": "Route {}{}. Pins can be dragged, movement starts with live location"
 },
 "Медиа в Google Drive": {
  "en": "Media to Google Drive"
 },
 "Месяц": {
  "en": "Month"
 },
 "Метка": {
  "en": "Label"
 },
 "Метка «сохранил»": {
  "en": "“Saved you” label"
 },
 "Метка «сохранил» или «не сохранил» видна в шапке чата и в профиле собеседника, только для тех, кого вы сами сохранили.\n\nЗаметка в шапке чата это первая строка вашей заметки из профиля собеседника. Правится в профиле через «Изменить».\n\nШаблоны вставляются кнопкой в поле ввода, она появляется после добавления первого шаблона. «Все сообщения автора» есть в меню долгого нажатия на сообщение в группе. «Выгрузить чат в файл» в профиле собеседника, группы или канала. Там вся история текстом, с пометками удалённых и прежними версиями изменённых.\n\nБез сжатия фото и видео из галереи уходят оригиналом, файлом, как через «Отправить файлом». Получатель увидит файл, а не картинку в ленте. Предел размера 2 ГБ держит сервер Telegram, его не поднять.\n\nFace ID на чат ставится долгим нажатием на чат в списке, пункт «Закрыть Face ID». У закрытого чата скрыт текст последнего сообщения и предпросмотр, открывается он после проверки и снова закрывается, когда приложение уходит в фон. Снять замок или выключить эту настройку можно только после проверки.\n\n«Мои дела» открываются из главных настроек, строка под «Моим профилем». Вид меняется кнопкой вверху, это лента, день по часам и месяц. Выключенный тумблер прячет строку, сами дела и напоминания остаются. «Пароли» там же, открываются по Face ID, записи лежат в Keychain только на этом телефоне.\n\n«Напомнить позже» есть в меню долгого нажатия на чат в списке и на сообщение. Напоминание ложится делом в «Мои дела», уведомление открывает этот чат.\n\nВключённое или выключенное применяется при следующем открытии экрана.": {
  "en": "The “Saved you” or “Hasn't saved you” label appears in the chat header and in the contact's profile, only for people you have saved yourself.\n\nThe note in the chat header is the first line of your note from the contact's profile. Edit it in the profile via “Edit”.\n\nTemplates are inserted with a button in the input field, it appears after you add the first template. “All messages from author” is in the long-press menu of a message in a group. “Export chat to file” is in the profile of a contact, group or channel. It contains the whole history as text, with deleted messages marked and previous versions of edited ones.\n\nWithout compression, photos and videos from the gallery are sent as originals, as files, like “Send as File”. The recipient sees a file, not a picture in the chat. The 2 GB size limit is enforced by Telegram's server and can't be raised.\n\nFace ID for a chat is set by long-pressing the chat in the list and choosing “Lock with Face ID”. A locked chat hides the last message text and preview, opens after verification and locks again when the app goes to the background. Removing the lock or turning off this setting requires verification.\n\n“My Tasks” opens from the main settings, the row under “My Profile”. The view is switched with the button at the top, it's the feed, day by hour and month. Turning the switch off hides the row, the tasks and reminders stay. “Passwords” is there too, opens with Face ID, entries are stored in Keychain on this phone only.\n\n“Remind me later” is in the long-press menu of a chat in the list and of a message. The reminder becomes a task in “My Tasks”, the notification opens that chat.\n\nTurning things on or off applies the next time the screen opens."
 },
 "Метка ставится долгим нажатием на чат в списке, пункт «Метки». На одном чате может быть несколько меток, группы тоже подходят. Метки видны под именем чата и рядом над списком чатов, нажатие на метку открывает её чаты. Хранятся только на этом телефоне, собеседники их не видят.": {
  "en": "To label a chat, long-press it in the list and choose “Labels”. A chat can have several labels, groups work too. Labels appear under the chat name and in the row above the chat list, tapping a label opens its chats. They are stored only on this phone, other people don't see them."
 },
 "Метки": {
  "en": "Labels"
 },
 "Метки на чаты": {
  "en": "Chat labels"
 },
 "Метки, {}": {
  "en": "Labels, {}"
 },
 "Меток пока нет. Создайте первую, она сразу встанет на «{}».": {
  "en": "No labels yet. Create the first one, it will be applied to “{}” right away."
 },
 "Мини-приложения ботов": {
  "en": "Bot Mini Apps"
 },
 "Можно в несколько строк. Переносы сохранятся.": {
  "en": "Multiple lines are fine. Line breaks are kept."
 },
 "Мои дела": {
  "en": "My Tasks"
 },
 "Мой профиль": {
  "en": "My Profile"
 },
 "НАЗВАНИЕ": {
  "en": "NAME"
 },
 "НАПОМНИТЬ": {
  "en": "REMIND"
 },
 "На «вы»": {
  "en": "Formal"
 },
 "На «ты»": {
  "en": "Informal"
 },
 "На неделе": {
  "en": "This week"
 },
 "Нажмите плюс вверху, чтобы добавить дело на этот день.": {
  "en": "Tap plus at the top to add a task for this day."
 },
 "Найдено {}. Личный чат и общие группы, нажатие открывает сообщение.": {
  "en": "Found {}. Private chat and common groups, tap to open a message."
 },
 "Найти и выгрузить": {
  "en": "Find and upload"
 },
 "Написал {}. Текст можно поправить здесь же, потом «Заменить» вверху.": {
  "en": "Written by {}. You can edit the text here, then tap “Replace” at the top."
 },
 "Напоминание": {
  "en": "Reminder"
 },
 "Напомнить позже": {
  "en": "Remind me later"
 },
 "Напомню {}. Дело лежит в «Моих делах».": {
  "en": "I'll remind you {}. The task is in “My Tasks”."
 },
 "Например, Cloudflare": {
  "en": "For example, Cloudflare"
 },
 "Например, ждёт оплату": {
  "en": "For example, awaiting payment"
 },
 "Например, строже и без приветствия": {
  "en": "For example, stricter and without a greeting"
 },
 "Напрямую": {
  "en": "Straight"
 },
 "Настоящая": {
  "en": "Real"
 },
 "Не получилось, {}.": {
  "en": "Didn't work, {}."
 },
 "Не сохранил": {
  "en": "Hasn't saved you"
 },
 "Не удалось загрузить {}. {}": {
  "en": "Couldn't upload {}. {}"
 },
 "Не удалось записать файл": {
  "en": "Couldn't write the file"
 },
 "Не удалось расшифровать. Проверьте язык в Dkx, раздел «Расшифровка голосовых», и что запись загружена.": {
  "en": "Couldn't transcribe. Check the language in Dkx, “Voice transcription” section, and that the recording is downloaded."
 },
 "Недавние звонки": {
  "en": "Recent Calls"
 },
 "Необязательно": {
  "en": "Optional"
 },
 "Ничего не нашлось": {
  "en": "Nothing found"
 },
 "Новая запись": {
  "en": "New entry"
 },
 "Новая метка": {
  "en": "New label"
 },
 "Новое дело": {
  "en": "New task"
 },
 "Новый шаблон": {
  "en": "New template"
 },
 "Номер": {
  "en": "Phone"
 },
 "Нужно войти в Google заново": {
  "en": "Sign in to Google again"
 },
 "ОБРАЩЕНИЕ": {
  "en": "FORM OF ADDRESS"
 },
 "ОТЛАДКА": {
  "en": "DEBUG"
 },
 "Обратно": {
  "en": "Reverse"
 },
 "Опрос": {
  "en": "Poll"
 },
 "Опустить ниже": {
  "en": "Move down"
 },
 "Оранжевый": {
  "en": "Orange"
 },
 "Основной": {
  "en": "Default"
 },
 "Отвязать аккаунт": {
  "en": "Unlink account"
 },
 "Отдаётся настоящая геопозиция": {
  "en": "Sharing the real location"
 },
 "Открепить у себя": {
  "en": "Unpin locally"
 },
 "Открыть закрытый чат": {
  "en": "Open locked chat"
 },
 "Открыть пароли": {
  "en": "Open passwords"
 },
 "Открыть ссылку": {
  "en": "Open link"
 },
 "Открыть чат": {
  "en": "Open chat"
 },
 "Отладочное меню Telegram": {
  "en": "Telegram debug menu"
 },
 "Отмена": {
  "en": "Cancel"
 },
 "Отмеченные метки видны под именем «{}» в списке чатов. Цвет и название меняются в Dkx, раздел «Метки».": {
  "en": "Checked labels appear under “{}” in the chat list. Color and name can be changed in Dkx, “Labels” section."
 },
 "Отправить подарок": {
  "en": "Send a Gift"
 },
 "Оформление": {
  "en": "Appearance"
 },
 "ПЕРИОД": {
  "en": "PERIOD"
 },
 "ПОЛЯ, ВСЕ НЕОБЯЗАТЕЛЬНЫ": {
  "en": "FIELDS, ALL OPTIONAL"
 },
 "Панель на карте скрыта, приложение отдаёт настоящую геопозицию.": {
  "en": "The map panel is hidden, the app shares the real location."
 },
 "Панель подмены на карте": {
  "en": "Location override panel on map"
 },
 "Папки с чатами": {
  "en": "Chat Folders"
 },
 "Пароли": {
  "en": "Passwords"
 },
 "Пароль": {
  "en": "Password"
 },
 "Пароль скопирован, буфер очистится через 2 минуты": {
  "en": "Password copied, the clipboard will be cleared in 2 minutes"
 },
 "По": {
  "en": "To"
 },
 "По дорогам": {
  "en": "By roads"
 },
 "Повторно загрузить в Google Drive": {
  "en": "Upload to Google Drive again"
 },
 "Подмена настраивается прямо на карте, в экране отправки геопозиции. Там переключатель Настоящая, Точка или Маршрут, точки ставятся долгим нажатием на карту. Трансляция сама запускает движение по маршруту.\n\nДействует на трансляцию, отправку местоположения и запросы ботов. На системные карты и другие приложения не влияет.": {
  "en": "The override is set up right on the map, on the location sending screen. There is a Real, Point or Route switch, points are placed by long-pressing the map. Live location starts moving along the route by itself.\n\nApplies to live location, sending location and bot requests. Doesn't affect system maps or other apps."
 },
 "Поднять выше": {
  "en": "Move up"
 },
 "Подробнее": {
  "en": "More detailed"
 },
 "Поехали": {
  "en": "Go"
 },
 "Позже": {
  "en": "Later"
 },
 "Поиск идёт на сервере Telegram, поэтому находится и то, что не загружено на телефон. Перед выгрузкой покажу, сколько нашлось. Файлы грузятся фоном, ход виден в полосе вверху экрана, повторы на диск не попадут. За один раз до {} файлов.": {
  "en": "The search runs on Telegram's server, so it also finds files not downloaded to the phone. Before uploading you'll see how many were found. Files upload in the background, progress is shown in the bar at the top of the screen, duplicates won't be uploaded. Up to {} files at a time."
 },
 "Показать пароль": {
  "en": "Show password"
 },
 "Полные логи Telegram пишутся только по запросу. В отладочном меню включите Log to File, повторите проблему и нажмите Send Logs там же.": {
  "en": "Full Telegram logs are written only on request. In the debug menu, turn on Log to File, reproduce the problem and tap Send Logs there."
 },
 "Понятно": {
  "en": "OK"
 },
 "Почта": {
  "en": "Email"
 },
 "Привязать другой аккаунт": {
  "en": "Link another account"
 },
 "Приехали в точку Б": {
  "en": "Arrived at point B"
 },
 "Применить свой стиль": {
  "en": "Apply custom style"
 },
 "Проверить и сохранить": {
  "en": "Check and save"
 },
 "Проверяю…": {
  "en": "Checking…"
 },
 "Продающий": {
  "en": "Persuasive"
 },
 "Прокси": {
  "en": "Proxy"
 },
 "Просрочено": {
  "en": "Overdue"
 },
 "Пункт «В Google Drive» в меню медиа. Файлы уходят только на ваш диск, в папку Dkx.": {
  "en": "The “Save to Google Drive” item in the media menu. Files go only to your drive, into the Dkx folder."
 },
 "РАСШИФРОВКА ГОЛОСОВЫХ": {
  "en": "VOICE TRANSCRIPTION"
 },
 "Расшифровка без Premium": {
  "en": "Transcription without Premium"
 },
 "Розовый": {
  "en": "Pink"
 },
 "Русский": {
  "en": "Russian"
 },
 "С": {
  "en": "From"
 },
 "СМАЙЛИКИ": {
  "en": "EMOJI"
 },
 "СООБЩЕНИЯ": {
  "en": "MESSAGES"
 },
 "СТИЛЬ": {
  "en": "STYLE"
 },
 "Сами экраны не пропадают. Контакты открываются из списка чатов при создании чата, звонки из «Недавних звонков» в настройках, если эта строка не спрятана.": {
  "en": "The screens themselves stay available. Contacts open from the chat list when starting a new chat, calls from “Recent Calls” in settings, if that row isn't hidden."
 },
 "Свои даты": {
  "en": "Custom dates"
 },
 "Свой стиль": {
  "en": "Custom style"
 },
 "Сегодня": {
  "en": "Today"
 },
 "Сегодня в 19:00": {
  "en": "Today at 19:00"
 },
 "Сегодня запросов {}. Русский и английский улучшает GLM, узбекский Gemini, при сбое запрос уходит в другой сервис. Бесплатный Gemini может показывать тексты сотрудникам Google, личное туда лучше не отправлять.": {
  "en": "Requests today {}. Russian and English are improved by GLM, Uzbek by Gemini, on failure the request goes to the other service. Free Gemini may show texts to Google staff, better not to send anything personal."
 },
 "Синий": {
  "en": "Blue"
 },
 "Скопировать логин": {
  "en": "Copy login"
 },
 "Скопировать пароль": {
  "en": "Copy password"
 },
 "Скрыто Face ID": {
  "en": "Hidden by Face ID"
 },
 "Скрыть ленту историй": {
  "en": "Hide stories bar"
 },
 "Скрыть пароль": {
  "en": "Hide password"
 },
 "Скрыть разделы": {
  "en": "Hide sections"
 },
 "Сначала войдите в Google в настройках Dkx": {
  "en": "Sign in to Google in Dkx settings first"
 },
 "Снять Face ID": {
  "en": "Remove Face ID"
 },
 "Снять Face ID с чата": {
  "en": "Remove Face ID from chat"
 },
 "Снять метку можно долгим нажатием на чат, пункт «Метки».": {
  "en": "To remove a label, long-press the chat and choose “Labels”."
 },
 "Сообщение": {
  "en": "Message"
 },
 "Сообщение с вложением": {
  "en": "Message with attachment"
 },
 "Сообщений {}": {
  "en": "Messages {}"
 },
 "Сохранил": {
  "en": "Saved you"
 },
 "Сохранять историю правок": {
  "en": "Save edit history"
 },
 "Сохранять удалённые": {
  "en": "Keep deleted"
 },
 "Сохранён ключ {}": {
  "en": "Saved key {}"
 },
 "Список «Без ответа»": {
  "en": "“Unanswered” list"
 },
 "Список открывается долгим нажатием на вкладку «Чаты». В нём личные чаты, где последним написал собеседник, без ботов и архива. Сверху те, кто ждёт дольше всех.": {
  "en": "The list opens by long-pressing the “Chats” tab. It shows private chats where the other person wrote last, without bots and the archive. Those waiting longest are at the top."
 },
 "Сразу": {
  "en": "Immediately"
 },
 "Ссылка": {
  "en": "Link"
 },
 "Стикер": {
  "en": "Sticker"
 },
 "Стоим в точке. Метку можно перетащить пальцем": {
  "en": "Standing at the point. Drag the pin to move it"
 },
 "Стоп": {
  "en": "Stop"
 },
 "Текст шаблона": {
  "en": "Template text"
 },
 "Точка": {
  "en": "Point"
 },
 "Точка А есть. Долгое нажатие ставит Б": {
  "en": "Point A is set. Long-press to set B"
 },
 "У любого фото, видео, голосового или файла в меню долгого нажатия есть пункт «В Google Drive». Файлы грузятся фоном, ход виден в полосе вверху экрана. Папка Dkx, внутри по чатам, только на ваш диск. Права ограничены файлами, которые загрузило это приложение.": {
  "en": "Any photo, video, voice message or file has “Save to Google Drive” in its long-press menu. Files upload in the background, progress is shown in the bar at the top of the screen. A Dkx folder with a subfolder per chat, only on your drive. Access is limited to files uploaded by this app."
 },
 "УЛУЧШИТЬ ТЕКСТ": {
  "en": "IMPROVE TEXT"
 },
 "Убрать навязывание премиума": {
  "en": "Remove Premium upsells"
 },
 "Уведомления и звуки": {
  "en": "Notifications and Sounds"
 },
 "Удалить": {
  "en": "Delete"
 },
 "Удалить дело": {
  "en": "Delete task"
 },
 "Удалить дело?": {
  "en": "Delete task?"
 },
 "Удалить запись": {
  "en": "Delete entry"
 },
 "Удалить запись?": {
  "en": "Delete entry?"
 },
 "Удалить ключ": {
  "en": "Delete key"
 },
 "Удалить метку": {
  "en": "Delete label"
 },
 "Удалить метку?": {
  "en": "Delete label?"
 },
 "Удалить шаблон": {
  "en": "Delete template"
 },
 "Удалённое": {
  "en": "Deleted"
 },
 "Удалённые собеседником сообщения остаются в чате с пометкой «удалено». У отредактированных в контекстном меню доступна история правок.\n\nСекретные чаты и самоуничтожающиеся сообщения не затрагиваются.": {
  "en": "Messages deleted by the other person stay in the chat marked “deleted”. Edited messages have edit history in the context menu.\n\nSecret chats and self-destructing messages are not affected."
 },
 "Удалённых сообщений нет. Сохраняются только те, что собеседник удалил при включённом «Сохранять удалённые», и только если телефон успел их получить.": {
  "en": "No deleted messages. Only messages deleted while “Keep deleted” was on are saved, and only if the phone had received them."
 },
 "Уже было в Google Drive": {
  "en": "Already on Google Drive"
 },
 "Узбекский": {
  "en": "Uzbek"
 },
 "Улучшить текст": {
  "en": "Improve text"
 },
 "Устройства": {
  "en": "Devices"
 },
 "Файл": {
  "en": "File"
 },
 "Файл в очереди на Google Drive, ход загрузки вверху экрана": {
  "en": "File queued for Google Drive, progress at the top of the screen"
 },
 "Файлов {}": {
  "en": "Found {}"
 },
 "Файлов в очереди на Google Drive {}, ход загрузки вверху экрана": {
  "en": "{} files queued for Google Drive, progress at the top of the screen"
 },
 "Файлы": {
  "en": "Files"
 },
 "Фиолетовый": {
  "en": "Purple"
 },
 "Фото": {
  "en": "Photo"
 },
 "Фото и видео": {
  "en": "Photos and videos"
 },
 "Фото и видео без сжатия": {
  "en": "Photos and videos without compression"
 },
 "ЦВЕТ": {
  "en": "COLOR"
 },
 "ЧТО ВЫГРУЖАТЬ": {
  "en": "WHAT TO UPLOAD"
 },
 "Чат": {
  "en": "Chat"
 },
 "Чат {}": {
  "en": "Chat {}"
 },
 "Чат {} {}.txt": {
  "en": "Chat {} {}.txt"
 },
 "Чатов с этой меткой нет. Метка ставится долгим нажатием на чат, пункт «Метки».": {
  "en": "No chats with this label. To add it, long-press a chat and choose “Labels”."
 },
 "Через 3 часа": {
  "en": "In 3 hours"
 },
 "Через час": {
  "en": "In 1 hour"
 },
 "Что сделать": {
  "en": "What to do"
 },
 "ШАБЛОНЫ {}": {
  "en": "TEMPLATES {}"
 },
 "Шаблон": {
  "en": "Template"
 },
 "Шаблонов нет, добавьте в настройках Dkx": {
  "en": "No templates yet, add them in Dkx settings"
 },
 "Шаблоны": {
  "en": "Templates"
 },
 "Шаблоны быстрых ответов": {
  "en": "Quick reply templates"
 },
 "Шаблоны ответов": {
  "en": "Reply templates"
 },
 "Энергосбережение": {
  "en": "Power Saving"
 },
 "Я": {
  "en": "Me"
 },
 "ЯЗЫК": {
  "en": "LANGUAGE"
 },
 "Язык": {
  "en": "Language"
 },
 "весь день": {
  "en": "all day"
 },
 "вс": {
  "en": "Su"
 },
 "вт": {
  "en": "Tu"
 },
 "вчера": {
  "en": "yesterday"
 },
 "дел нет": {
  "en": "no tasks"
 },
 "завтра": {
  "en": "tomorrow"
 },
 "загружено {}": {
  "en": "uploaded {}"
 },
 "заметка": {
  "en": "note"
 },
 "ключ не подходит": {
  "en": "the key is invalid"
 },
 "лимит на сегодня или сервис перегружен": {
  "en": "daily limit reached or the service is overloaded"
 },
 "логин": {
  "en": "login"
 },
 "на диске ": {
  "en": "on Drive "
 },
 "на сегодня дел нет": {
  "en": "no tasks for today"
 },
 "напомнит ": {
  "en": "reminds "
 },
 "не подключён": {
  "en": "not connected"
 },
 "не сохранил": {
  "en": "hasn't saved you"
 },
 "не удалось {}": {
  "en": "failed {}"
 },
 "не удалось подготовить файл": {
  "en": "couldn't prepare the file"
 },
 "не удалось проверить": {
  "en": "couldn't verify"
 },
 "неизвестно": {
  "en": "unknown"
 },
 "нет": {
  "en": "none"
 },
 "нет ключей. Вставьте ключ Gemini или GLM в Dkx, раздел «Улучшить текст»": {
  "en": "no keys. Add a Gemini or GLM key in Dkx, “Improve text” section"
 },
 "нет связи с сервисом": {
  "en": "can't reach the service"
 },
 "нет сервиса": {
  "en": "no service"
 },
 "номер": {
  "en": "phone"
 },
 "ответ {}": {
  "en": "response {}"
 },
 "пароль": {
  "en": "password"
 },
 "пн": {
  "en": "Mo"
 },
 "подключён": {
  "en": "connected"
 },
 "последние": {
  "en": "recent"
 },
 "почта": {
  "en": "email"
 },
 "пт": {
  "en": "Fr"
 },
 "сб": {
  "en": "Sa"
 },
 "сегодня": {
  "en": "today"
 },
 "сейчас": {
  "en": "now"
 },
 "сейчас\n": {
  "en": "now\n"
 },
 "сервис вернул пустой ответ": {
  "en": "the service returned an empty response"
 },
 "сервис не ответил за 30 секунд": {
  "en": "the service didn't respond in 30 seconds"
 },
 "сервис не принял запрос": {
  "en": "the service rejected the request"
 },
 "сохранил": {
  "en": "saved you"
 },
 "ср": {
  "en": "We"
 },
 "ссылка": {
  "en": "link"
 },
 "только что": {
  "en": "just now"
 },
 "удалено ": {
  "en": "deleted "
 },
 "уже были {}": {
  "en": "already there {}"
 },
 "чат": {
  "en": "chat"
 },
 "чт": {
  "en": "Th"
 }
}
"""#
