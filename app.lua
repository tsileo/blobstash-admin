local template = require('template')
local router = require('router').new()
local gs = require('gitserver')

router:get('/git', function(params)
  local data = {}
  -- TODO(tsileo): support /git/:ns
  for _, ns in ipairs(gs.namespaces()) do
    for _, repo in ipairs(gs.repositories(ns)) do
      table.insert(data, {ns = ns, repo = repo })
    end
  end

  -- TODO(tsileo): only one template for git (with "if"
  app.response:write(template.render('git_repo.html', { data = data }))
end)

router:get('/git/:ns/:repo/commit/:hash', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree)
  local repo = gs.repo(params.ns, params.repo)
  local commit = repo:get_commit(params.hash)
  app.response:write(template.render('git_repo.html', { name = params.name, ns = params.ns, repo = params.repo, commit = commit }))
end)

router:get('/git/:ns/:repo/log', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree)
  local repo = gs.repo(params.ns, params.repo)
  local log = repo:log()
  app.response:write(template.render('git_repo.html', { name = params.name, ns = params.ns, repo = params.repo, log = log }))
end)

router:get('/git/:ns/:repo/file/:hash/:name', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree)
  local repo = gs.repo(params.ns, params.repo)
  local file = repo:get_file(params.hash)
  app.response:write(template.render('git_repo.html', { name = params.name, file = file, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree/:hash', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree), in the URL, JSON encoded
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:get_tree(params.hash)
  app.response:write(template.render('git_repo.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:tree()
  -- TODO(tsileo): repo:get_readme() as a str
  app.response:write(template.render('git_repo.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/refs', function(params)
  local repo = gs.repo(params.ns, params.repo)
  -- TODO(tsileo): repo:get_readme() as a str
  app.response:write(template.render('git_repo.html', { ns = params.ns, repo = params.repo, refs = repo:refs() }))
end)

router:get('/git/:ns/:repo', function(params)
  local repo = gs.repo(params.ns, params.repo)
  -- TODO(tsileo): repo:get_readme() as a str
  app.response:write(template.render('git_repo.html', { ns = params.ns, repo = params.repo, summary = repo:summary() }))
end)

router:run()
