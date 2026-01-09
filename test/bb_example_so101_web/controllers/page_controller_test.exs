defmodule BB.Example.SO101Web.PageControllerTest do
  use BB.Example.SO101Web.ConnCase

  test "GET / renders BB Dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "BB Dashboard"
  end
end
