defmodule LightCDP.ErrorsTest do
  use ExUnit.Case, async: true

  alias LightCDP.{
    ElementNotFoundError,
    TimeoutError,
    JavaScriptError,
    CDPError,
    ConnectionError
  }

  describe "ElementNotFoundError" do
    test "new/1 builds from selector" do
      err = ElementNotFoundError.new("#login")
      assert %ElementNotFoundError{selector: "#login"} = err
      assert Exception.message(err) =~ "#login"
    end
  end

  describe "TimeoutError" do
    test "new/1 builds with defaults" do
      err = TimeoutError.new()
      assert %TimeoutError{} = err
      assert Exception.message(err) =~ "timed out"
    end

    test "new/1 accepts operation and timeout" do
      err = TimeoutError.new(operation: :navigate, timeout_ms: 5_000)
      assert %TimeoutError{operation: :navigate, timeout_ms: 5_000} = err
      assert Exception.message(err) =~ "navigate"
    end
  end

  describe "JavaScriptError" do
    test "new/1 builds from description" do
      err = JavaScriptError.new("ReferenceError: x is not defined")
      assert %JavaScriptError{} = err
      assert Exception.message(err) =~ "ReferenceError"
    end
  end

  describe "CDPError" do
    test "new/2 builds from code and message" do
      err = CDPError.new(-31998, "UnknownMethod")
      assert %CDPError{code: -31998} = err
      assert Exception.message(err) =~ "UnknownMethod"
    end
  end

  describe "ConnectionError" do
    test "new/1 builds from reason" do
      err = ConnectionError.new(:econnrefused)
      assert %ConnectionError{reason: :econnrefused} = err
      assert Exception.message(err) =~ "econnrefused"
    end
  end
end
