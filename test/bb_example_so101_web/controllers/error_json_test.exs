# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101Web.ErrorJSONTest do
  use BB.Example.SO101Web.ConnCase, async: true

  alias BB.Example.SO101Web.ErrorJSON

  test "renders 404" do
    assert ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
