@talent.factory 'Entry', ["$resource", "$http", ($resource, $http) ->
  Entry = $resource "/entries/:id.json", { id: "@id" }, { update: { method: "PUT" } }
  Entry::blacklist = -> $http.post "/entries/#{ @id }/blacklist.json"
  Entry::hasProfile = -> @author and @author.profile? and not _.isEmpty @author.profile
  Entry
]


@talent.factory 'Search', ["$resource", ($resource) ->
  $resource "/searches/:id.json", { id: "@id" }, { update: { method: "PUT" } }
]


@talent.factory 'Folder', ["$resource", "$http", ($resource, $http) ->
  Folder = $resource "/folders/:id.json", { id: "@id" }, { update: { method: "PUT" } }
  Folder.fetch        = (id, callback) -> $http.get("/entries.json?folder_id=#{ id }").then (response) -> callback(response.data)
  Folder::addEntry    = (entry) ->
    $http.put "/folders/#{ @id }/add_entry.json", entry_id: entry.id
    @entries.push entry.id
  Folder::removeEntry = (entry) -> $http.put "/folders/#{ @id }/remove_entry.json", entry_id: entry.id
  Folder::contains    = (entry) -> entry.id in @entries if @entries? and entry?
  Folder
]
