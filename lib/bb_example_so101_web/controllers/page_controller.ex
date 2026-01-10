# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101Web.PageController do
  use BB.Example.SO101Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
