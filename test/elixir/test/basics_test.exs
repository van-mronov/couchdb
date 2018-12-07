defmodule BasicsTest do
  use CouchTestCase

  @moduletag :basics

  @moduledoc """
  Test CouchDB basics.
  This is a port of the basics.js suite
  """

  test "Session contains adm context" do
    assert %{
             "userCtx" => %{
               "name" => "adm",
               "roles" => ["_admin"]
             }
           } = json_response(Couch.get("/_session"), 200)
  end

  test "Welcome endpoint" do
    assert %{"couchdb" => "Welcome"} = json_response(Couch.get("/"), 200)
  end

  @tag :with_db
  test "PUT on existing DB should return 412 instead of 500", %{db_name: db_name} do
    assert json_response(Couch.put("/#{db_name}"), 412) == %{
             "error" => "file_exists",
             "reason" => "The database could not be created, the file already exists."
           }
  end

  @tag :with_db_name
  test "Creating a new DB should return location header", context do
    db_name = context[:db_name]
    {:ok, resp} = create_db(db_name)
    msg = "Should return Location header for new db"
    assert String.ends_with?(resp.headers["location"], db_name), msg
    {:ok, _} = delete_db(db_name)
  end

  @tag :with_db_name
  test "Creating a new DB with slashes should return Location header (COUCHDB-411)",
       context do
    db_name = context[:db_name] <> "%2Fwith_slashes"
    {:ok, resp} = create_db(db_name)
    msg = "Should return Location header for new db"
    assert String.ends_with?(resp.headers["location"], db_name), msg
    {:ok, _} = delete_db(db_name)
  end

  @tag :with_db
  test "Created database has appropriate db info name", %{db_name: db_name} do
    assert %{"db_name" => ^db_name} = json_response(Couch.get("/#{db_name}"), 200)
  end

  @tag :with_db
  test "Database should be in _all_dbs", %{db_name: db_name} do
    assert db_name in json_response(Couch.get("/_all_dbs"), 200)
  end

  @tag :with_db
  test "Empty database should have zero docs", %{db_name: db_name} do
    assert %{"doc_count" => 0} = json_response(Couch.get("/#{db_name}"), 200)
  end

  @tag :with_db
  test "Create a document and save it to the database", %{db_name: db_name} do
    id = "0"
    resp = Couch.post("/#{db_name}", body: %{_id: id, a: 1, b: 1})
    assert %{"id" => ^id, "rev" => rev} = json_response(resp, 201)

    resp = Couch.get("/#{db_name}/#{id}")
    assert %{"_id" => ^id, "_rev" => ^rev} = json_response(resp, 200)
  end

  @tag :with_db
  test "Revs info status is available", %{db_name: db_name} do
    {:ok, _} = create_doc(db_name, sample_doc_foo())
    resp = Couch.get("/#{db_name}/foo", query: %{revs_info: true})

    assert %{
             "_revs_info" => [%{"status" => "available"} | _]
           } = json_response(resp, 200)
  end

  @tag :with_db
  test "Make sure you can do a seq=true option", %{db_name: db_name} do
    {:ok, _} = create_doc(db_name, sample_doc_foo())
    resp = Couch.get("/#{db_name}/foo", query: %{local_seq: true})
    assert %{"_local_seq" => 1} = json_response(resp, 200)
  end

  @tag :with_db
  test "Can create several documents", %{db_name: db_name} do
    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "1", a: 2, b: 4}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "2", a: 3, b: 9}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "3", a: 4, b: 16}), 201)

    retry_until(fn ->
      json_response(Couch.get("/#{db_name}"), 200)["doc_count"] == 3
    end)
  end

  @tag :pending
  @tag :with_db
  test "Regression test for COUCHDB-954", context do
    db_name = context[:db_name]
    doc = %{:_id => "COUCHDB-954", :a => 1}

    resp1 = Couch.post("/#{db_name}", body: doc)
    assert resp1.body["ok"]
    old_rev = resp1.body["rev"]

    doc = Map.put(doc, :_rev, old_rev)
    resp2 = Couch.post("/#{db_name}", body: doc)
    assert resp2.body["ok"]
    _new_rev = resp2.body["rev"]

    # TODO: enable chunked encoding
    # resp3 = Couch.get("/#{db_name}/COUCHDB-954", [query: %{:open_revs => "[#{old_rev}, #{new_rev}]"}])
    # assert length(resp3.body) == 2, "Should get two revisions back"
    # resp3 = Couch.get("/#{db_name}/COUCHDB-954", [query: %{:open_revs => "[#{old_rev}]", :latest => true}])
    # assert resp3.body["_rev"] == new_rev
  end

  @tag :with_db
  test "Simple map functions", %{db_name: db_name} do
    map_fun = "function(doc) { if (doc.a==4) { emit(null, doc.b); } }"
    red_fun = "function(keys, values) { return sum(values); }"
    map_doc = %{views: %{baz: %{map: map_fun}}}
    red_doc = %{views: %{baz: %{map: map_fun, reduce: red_fun}}}

    # Bootstrap database and ddoc
    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "0", a: 1, b: 1}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "1", a: 2, b: 4}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "2", a: 3, b: 9}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{_id: "3", a: 4, b: 16}), 201)

    assert %{"ok" => true} =
             json_response(Couch.put("/#{db_name}/_design/foo", body: map_doc), 201)

    assert %{"ok" => true} =
             json_response(Couch.put("/#{db_name}/_design/bar", body: red_doc), 201)

    assert %{"doc_count" => 6} = json_response(Couch.get("/#{db_name}"), 200)

    # Initial view query test
    assert %{
             "total_rows" => 1,
             "rows" => [%{"value" => 16} | _]
           } = json_response(Couch.get("/#{db_name}/_design/foo/_view/baz"), 200)

    # Modified doc and test for updated view results
    doc0 = Couch.get("/#{db_name}/0").body
    doc0 = Map.put(doc0, :a, 4)
    assert %{"ok" => true} = json_response(Couch.put("/#{db_name}/0", body: doc0), 201)

    retry_until(fn ->
      response = Couch.get("/#{db_name}/_design/foo/_view/baz")
      json_response(response, 200)["total_rows"] == 2
    end)

    # Write 2 more docs and test for updated view results
    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{a: 3, b: 9}), 201)

    assert %{"ok" => true} =
             json_response(Couch.post("/#{db_name}", body: %{a: 4, b: 16}), 201)

    retry_until(fn ->
      response = Couch.get("/#{db_name}/_design/foo/_view/baz")
      json_response(response, 200)["total_rows"] == 3
    end)

    assert %{"doc_count" => 8} = json_response(Couch.get("/#{db_name}"), 200)

    # Test reduce function
    assert %{
             "rows" => [%{"value" => 33} | _]
           } = json_response(Couch.get("/#{db_name}/_design/bar/_view/baz"), 200)

    # Delete doc and test for updated view results
    %{"_rev" => rev} = json_response(Couch.get("/#{db_name}/0"), 200)
    assert %{"ok" => true} = json_response(Couch.delete("/#{db_name}/0?rev=#{rev}"), 200)

    retry_until(fn ->
      json_response(Couch.get("/#{db_name}/_design/foo/_view/baz"), 200)["total_rows"] ==
        2
    end)

    assert %{"doc_count" => 7} = json_response(Couch.get("/#{db_name}"), 200)
    assert %{"error" => _error} = json_response(Couch.get("/#{db_name}/0"), 404)
    assert json_response(Couch.get("/#{db_name}/0?rev=#{rev}"), 200)
  end

  @tag :with_db
  test "POST doc response has a Location header", context do
    db_name = context[:db_name]
    resp = Couch.post("/#{db_name}", body: %{:foo => :bar})
    assert resp.body["ok"]
    loc = resp.headers["Location"]
    assert loc, "should have a Location header"
    locs = Enum.reverse(String.split(loc, "/"))
    assert hd(locs) == resp.body["id"]
    assert hd(tl(locs)) == db_name
  end

  @tag :with_db
  test "POST doc with an _id field isn't overwritten by uuid", %{db_name: db_name} do
    resp = Couch.post("/#{db_name}", body: %{_id: "oppossum", yar: "matey"})
    assert %{"id" => "oppossum", "ok" => true} = json_response(resp, 201)
    assert %{"yar" => "matey"} = json_response(Couch.get("/#{db_name}/oppossum"), 200)
  end

  @tag :pending
  @tag :with_db
  test "PUT doc has a Location header", context do
    db_name = context[:db_name]
    resp = Couch.put("/#{db_name}/newdoc", body: %{:a => 1})
    assert String.ends_with?(resp.headers["location"], "/#{db_name}/newdoc")
    # TODO: make protocol check use defined protocol value
    assert String.starts_with?(resp.headers["location"], "http")
  end

  @tag :with_db
  test "DELETE'ing a non-existent doc should 404", %{db_name: db_name} do
    assert json_response(Couch.delete("/#{db_name}/doc-does-not-exist"), 404)
  end

  @tag :with_db
  test "Check for invalid document members", %{db_name: db_name} do
    bad_docs = [
      {:goldfish, %{_zing: 4}},
      {:zebrafish, %{_zoom: "hello"}},
      {:mudfish, %{zane: "goldfish", _fan: "something smells delicious"}},
      {:tastyfish, %{_bing: %{"wha?" => "soda can"}}}
    ]

    Enum.each(bad_docs, fn {id, doc} ->
      assert %{
               "error" => "doc_validation"
             } = json_response(Couch.put("/#{db_name}/#{id}", body: doc), 400)

      assert %{
               "error" => "doc_validation"
             } = json_response(Couch.post("/#{db_name}", body: doc), 400)
    end)
  end

  @tag :with_db
  test "PUT error when body not an object", %{db_name: db_name} do
    assert %{
             "error" => "bad_request",
             "reason" => "Document must be a JSON object"
           } = json_response(Couch.put("/#{db_name}/bar", body: "[]"), 400)
  end

  @tag :with_db
  test "_bulk_docs POST error when body not an object", %{db_name: db_name} do
    assert %{
             "error" => "bad_request",
             "reason" => "Request body must be a JSON object"
           } = json_response(Couch.post("/#{db_name}/_bulk_docs", body: "[]"), 400)
  end

  @tag :with_db
  test "_all_docs POST error when multi-get is not a {'key': [...]} structure", context do
    %{db_name: db_name} = context

    assert %{
             "error" => "bad_request",
             "reason" => "Request body must be a JSON object"
           } = json_response(Couch.post("/#{db_name}/_all_docs", body: "[]"), 400)

    assert %{
             "error" => "bad_request",
             "reason" => "`keys` body member must be an array."
           } = json_response(Couch.post("/#{db_name}/_all_docs", body: %{keys: 1}), 400)
  end

  @tag :with_db
  test "oops, the doc id got lost in code nirwana", %{db_name: db_name} do
    assert %{
             "error" => "bad_request",
             "reason" =>
               "You tried to DELETE a database with a ?=rev parameter. Did you mean to DELETE a document instead?"
           } = json_response(Couch.delete("/#{db_name}/?rev=foobarbaz"), 400)
  end

  @tag :pending
  @tag :with_db
  test "On restart, a request for creating an already existing db can not override",
       _context do
    # TODO
    assert true
  end
end
