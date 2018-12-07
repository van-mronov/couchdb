defmodule Couch.ConnTest do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1, assert: 2]

  alias HTTPotion.Response

  def response(%Response{status_code: status, body: body}, given) do
    if given == status do
      body
    else
      raise "expected response with status #{given}, got: #{status}, with body:\n#{
              inspect(body)
            }"
    end
  end

  def json_response(resp, status) do
    body = response(resp, status)
    # _ = response_content_type(conn, :json)
    #
    # Phoenix.json_library().decode!(body)

    body
  end
end
