local template = require('template')
local router = require('router').new()
local gs = require('gitserver')
local kvs = require('kvstore')
local ft = require('filetree')
local bs = require('blobstore')

router:get('/', function(params)
  app.response:write(template.render('index.html', 'layout.html', {}))
end)

router:get('/kvstore', function(params)
  if app.request:args():get("key") ~= "" then
    local kv = kvs.key(app.request:args():get("key"), app.request:args():get("version"))
    app.response:write(template.render('kvstore.html', 'layout.html', { kv = kv }))
    return
  end
  local keys, cursor = kvs.keys(app.request:args():get("cursor"))
  app.response:write(template.render('kvstore.html', 'layout.html', { keys = keys, cursor = cursor }))
end)

router:get('/blobstore', function(params)
  local blobs, cursor = bs.blobs("")
  app.response:write(template.render('blobstore.html', 'layout.html', { blobs = blobs }))
end)

router:get('/blobstore/:hash', function(params)
  local data, cursor = bs.get(params.hash)
  app.response:write(template.render('blobstore.html', 'layout.html', { blobs = nil, data = data, hash = params.hash }))
end)

router:get('/filetree', function(params)
  local data = ft.iter_fs()
  app.response:write(template.render('filetree.html', 'layout.html', { data = data }))
end)

router:get('/filetree/:ref/:name/:cref', function(params)
  local node, path = ft.node(params.ref, params.cref)
  if node.name == '_root' then
      node.name = name
  end
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = node, path = path }))
end)

router:get('/filetree/:ref/:name', function(params)
  local root = ft.fs(params.ref)
  root.name = params.name
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = root }))
end)

router:get('/docstore', function(params)
  local collections = { 'test' }
  app.response:write(template.render('docstore.html', 'layout.html', { collections = collections }))
end)

router:get('/docstore/:col', function(params)
  app.response:write(template.render('docstore.html', 'layout.html', { col = params.col, collections = {} }))
end)

router:get('/git', function(params)
  local data = {}
  -- TODO(tsileo): support /git/:ns
  for _, ns in ipairs(gs.namespaces()) do
    for _, repo in ipairs(gs.repositories(ns)) do
      table.insert(data, {ns = ns, repo = repo })
    end
  end
  app.response:write(template.render('git_repo.html', 'layout.html', { data = data }))
end)

router:get('/git/:ns/:repo/commit/:hash', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local commit = repo:get_commit(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, ns = params.ns, repo = params.repo, commit = commit }))
end)

router:get('/git/:ns/:repo/log', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local log = repo:log()
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, ns = params.ns, repo = params.repo, log = log }))
end)

router:get('/git/:ns/:repo/file/:hash/:name/plain', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local file = repo:get_file(params.hash)
  local dl = false
  if app.request:args():get("dl") == "1" then
    dl = true
    app.response:headers():set("Content-Disposition", "attachment; filename=" .. params.name)
  end

  if not file.is_binary or dl then
    app.response:write(file.contents)
    return
  end
  return '[binary file, please donwload it]'
end)

router:get('/git/:ns/:repo/file/:hash/:name', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local file = repo:get_file(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, file = file, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree/:hash', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree), in the URL, JSON encoded
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:get_tree(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:tree()
  app.response:write(template.render('git_repo.html', 'layout.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/refs', function(params)
  local repo = gs.repo(params.ns, params.repo)
  app.response:write(template.render('git_repo.html', 'layout.html', { ns = params.ns, repo = params.repo, refs = repo:refs() }))
end)

router:get('/git/:ns/:repo', function(params)
  local repo = gs.repo(params.ns, params.repo)
  app.response:write(template.render('git_repo.html', 'layout.html', { ns = params.ns, repo = params.repo, summary = repo:summary() }))
end)

router:run()
