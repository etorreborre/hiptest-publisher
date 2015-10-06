require 'spec_helper'
require 'webmock/rspec'
require_relative '../lib/hiptest-publisher'

describe Hiptest::Publisher do

  let(:output_dir) {
    @output_dir_created = true
    Dir.mktmpdir
  }

  before(:each) {
    # partially prevent printing on stdout during rspec run (hacky! comment to use pry correctly)
    allow(STDOUT).to receive(:print)
  }

  after(:each) {
    if @output_dir_created
      FileUtils.rm_rf(output_dir)
    end
  }

  describe "--language=ruby" do
    def run_publisher_command(*extra_args)
      stub_request(:get, "https://hiptest.net/publication/123456789/project?future=1").
        to_return(body: File.read('samples/xml_input/Hiptest publisher.xml'))
      stub_request(:get, "https://hiptest.net/publication/123456789/leafless_tests?future=1").
        to_return(body: File.read('samples/xml_input/Hiptest automation.xml'))
      args = [
        "--language", "ruby",
        "--output-directory", output_dir,
        "--token", "123456789",
      ] + extra_args
      publisher = Hiptest::Publisher.new(args, listeners: [ErrorListener.new])
      publisher.run
    end

    it "exports correctly in the golden case" do
      stub_request(:get, "https://hiptest.net/publication/123456789/project?future=1").
        to_return(body: File.read('samples/xml_input/Hiptest publisher.xml'))
      args = [
        "--language", "ruby",
        "--output-directory", output_dir,
        "--token", "123456789",
      ]
      publisher = Hiptest::Publisher.new(args, listeners: [ErrorListener.new])
      publisher.run
      expect_same_files("samples/expected_output/Hiptest publisher-rspec", output_dir)
    end

    it "displays exporting scenarios, actionwords and actionword signature" do
      run_publisher_command
      expect(STDOUT).to have_printed('Exporting scenarios')
      expect(STDOUT).to have_printed('Exporting actionwords')
      expect(STDOUT).to have_printed('Exporting actionword signature')
    end

    describe "--split-scenarios" do
      it "displays exporting scenario for each scenario" do
        run_publisher_command("--split-scenarios")
        expect(STDOUT).to have_printed('Exporting scenario "A scenario in a subfolder"')
        expect(STDOUT).to have_printed('Exporting scenario "show help"')
      end
    end

    describe "--leafless-export" do
      it "displays exporting tests" do
        run_publisher_command("--leafless-export")
        expect(STDOUT).to have_printed('Exporting tests')
      end

      describe "--split-scenarios" do
        it "displays exporting test for each test" do
          run_publisher_command("--leafless-export", "--split-scenarios")
          expect(STDOUT).to have_printed('Exporting test "A scenario in a subfolder"')
          expect(STDOUT).to have_printed('Exporting test "show help"')
        end
      end
    end

    describe "--only=list" do
      it "displays available categories (tests & actionwords)" do

        expect {
          run_publisher_command("--only=list")
        }.to output([
          'For language ruby, available file groups are',
          '  - tests',
          '  - actionwords',
          '',
          'Usage examples:',
          '',
          'To export only tests files:',
          '    hiptest-publisher --language=ruby --only=tests',
          '',
          'To export both tests and actionwords files:',
          '    hiptest-publisher --language=ruby --only=tests,actionwords',
          '',
        ].join("\n")).to_stdout
      end
    end

    describe "--only=actionwords" do
      it "limits export to actionwords files" do
        run_publisher_command("--only=actionwords")
        expect(STDOUT).to have_printed("Exporting actionwords")
        expect(STDOUT).to have_not_printed("Exporting scenarios")
      end

      it "also exports actionword signature file" do
        run_publisher_command("--only=actionwords")
        expect(STDOUT).to have_printed("Exporting actionword signature")
      end
    end

    describe "--actionwords-only" do
      it "limits export to actionwords files (but deprecated in favor of --only=actionwords)" do
        run_publisher_command("--actionwords-only")
        expect(STDOUT).to have_printed("Exporting actionwords")
        expect(STDOUT).to have_not_printed("Exporting scenarios")
      end

      it "also exports actionword signature file" do
        run_publisher_command("--actionwords-only")
        expect(STDOUT).to have_printed("Exporting actionword signature")
      end
    end

    describe "--only=tests" do
      it "limits export to tests files" do
        run_publisher_command("--only=tests")
        expect(STDOUT).to have_not_printed("Exporting actionwords")
        expect(STDOUT).to have_printed("Exporting scenarios")
      end

      it "does not export actionword signature file" do
        run_publisher_command("--only=tests")
        expect(STDOUT).to have_not_printed("Exporting actionword signature")
      end
    end

    describe "--tests-only" do
      it "limits export to tests files (but deprecated in favor of --only=tests)" do
        run_publisher_command("--tests-only")
        expect(STDOUT).to have_not_printed("Exporting actionwords")
        expect(STDOUT).to have_printed("Exporting scenarios")
      end

      it "does not export actionword signature file" do
        run_publisher_command("--tests-only")
        expect(STDOUT).to have_not_printed("Exporting actionword signature")
      end
    end

    def have_printed(message)
      have_received(:print).at_least(1).with(a_string_including(message))
    end

    def have_not_printed(message)
      have_received(:print).with(a_string_including(message)).at_most(0)
    end

    describe "actionwords modifications" do
      before(:each) do
        aw_signatures = YAML.load_file("samples/expected_output/Hiptest publisher-rspec/actionwords_signature.yaml")

        # simulate "Do something" has been deleted
        aw_signatures << {
          "name" => "Do something",
          "uid" => "a9bd8101-96bc-43d4-bd47-c429a60c6bdc",
          "parameters" => [{"name"=>"x"}]}

        # simulate "start publisher" has been created
        aw_signatures.reject! { |aw| aw["name"] == "start publisher" }

        # simulate "Parameters and assignements" has been renamed
        aw = aw_signatures.find {|e| e["name"] == "Parameters and assignements"}
        aw["name"] = "Parameters and assinements"

        # simulate "Control blocks" signature has changed
        aw = aw_signatures.find {|e| e["name"] == "Control blocks"}
        aw["parameters"] = []

        File.write("#{output_dir}/actionwords_signature.yaml", YAML.dump(aw_signatures))
      end

      describe "--show-actionwords-diff" do
        it "displays differences in actionwords" do
          expect {
            run_publisher_command("--show-actionwords-diff")
          }.to output(a_string_including([
            "1 action word deleted:",
            "- Do something",
            "",
            "1 action word created:",
            "- start publisher",
            "",
            "1 action word renamed:",
            "- Parameters and assinements => Parameters and assignements",
            "",
            "1 action word which signature changed:",
            "- Control blocks",
          ].join("\n"))).to_stdout
        end
      end

      describe "--show-actionwords-deleted" do
        it "displays the method names of deleted actionwords" do
          expect {
            run_publisher_command("--show-actionwords-deleted")
          }.to output(a_string_including('do_something')).to_stdout
        end
      end

      describe "--show-actionwords-created" do
        it "displays the method stubs of created actionwords" do
          expect {
            run_publisher_command("--show-actionwords-created")
          }.to output(a_string_including([
            'def start_publisher(options = {})',
            '  # TODO: Implement action: "start publisher with options #{options}"',
            '  raise NotImplementedError',
            'end',
          ].join("\n"))).to_stdout
        end
      end

      describe "--show-actionwords-renamed" do
        it "displays a tabular list of renamed actionwords with old and new method names" do
          expect {
            run_publisher_command("--show-actionwords-renamed")
          }.to output(a_string_including(
            "parameters_and_assinements\tparameters_and_assignements",
          )).to_stdout
        end
      end

      describe "--show-actionwords-signature-changed" do
        it "displays the method stubs of the modified actionwords with its new signature" do
          expect {
            run_publisher_command("--show-actionwords-signature-changed")
          }.to output(a_string_including([
            'def control_blocks(x)',
            '  # Tags: parameters dsltests',
            '  while ((x < 0))',
            '    x = x + 1',
            '  end',
            '  if ((x == 0))',
            '    # TODO: Implement result: "#{x} is now equal to zero"',
            '  else',
            '    control_blocks(x - 1)',
            '  end',
            '  raise NotImplementedError',
            'end',
          ].join("\n"))).to_stdout
        end
      end
    end
  end

  def expect_same_files(expected_directory, actual_directory)
    aggregate_failures "output files" do
      actual_files = Dir.entries(actual_directory).reject { |f| [".", ".."].include?(f) }
      expected_files = Dir.entries(expected_directory).reject { |f| [".", ".."].include?(f) }
      expect(actual_files).to match_array(expected_files)

      common_files = (actual_files & expected_files)
      common_files.each do |file|
        actual_content = File.read("#{actual_directory}/#{file}")
        expected_content = File.read("#{expected_directory}/#{file}")
        expect(actual_content).to eq(expected_content), "File #{file} output is different from its expected output"
      end
    end
  end

  describe "--help" do
    it 'displays help and exists' do
      expect {
        begin
          Hiptest::Publisher.new(["--help"])
          fail("it should have exited")
        rescue SystemExit
        end
      }.to output(a_string_including("Usage: ruby publisher.rb [options]")).to_stdout
    end
  end

  describe "without arguments" do
    it 'displays help and exists' do
      expect {
        begin
          Hiptest::Publisher.new([])
          fail("it should have exited")
        rescue SystemExit
        end
      }.to output(a_string_including("Usage: ruby publisher.rb [options]")).to_stdout
    end
  end

  describe "with invalid arguments" do
    let(:listeners) { [ErrorListener.new] }

    def run_publisher_command(*args)
      publisher = Hiptest::Publisher.new(args, listeners: listeners)
      publisher.run
    end

    def run_publisher_expecting_exit(*args)
      begin
        run_publisher_command(*args)
        fail("running publisher with args=#{args.inspect} should have exited")
      rescue SystemExit
        # ok, it was expected
      end
    end

    context "with missing token" do
      it "outputs an error message inviting to add --token argument" do
        expect {
          run_publisher_expecting_exit("--language", "ruby")
        }.to output(a_string_including("Missing argument --token: you must specify project secret token with --token=<project-token>")).to_stdout
      end
    end

    context "with bad token format" do
      it "outputs an error message that it must be numeric" do
        expect {
          run_publisher_expecting_exit("--token", "abc")
        }.to output(a_string_including("Invalid format --token=\"abc\": the project secret token must be numeric")).to_stdout
      end
    end

    context "with non-numeric test-run-id" do
      it "outputs an error message that it must be numeric" do
        expect {
          run_publisher_expecting_exit("--token", "123", "--test-run-id", "125e")
        }.to output(a_string_including("Invalid format --test-run-id=\"125e\": the test run id must be numeric")).to_stdout
      end
    end

    context "with unreadable config file" do
      let(:listeners) { [] }

      it "outputs an error message that the file could not be read" do
        expect {
          run_publisher_expecting_exit("--token", "123", "--config", "polop")
        }.to output(a_string_including("Error with --config: the file \"polop\" does not exist or is not readable")).to_stdout
      end
    end

    context "--output-directory" do
      before(:each) {
        stub_request(:get, "https://hiptest.net/publication/123/project?future=1").
          to_return(body: File.read('samples/xml_input/Hiptest publisher.xml'))
      }

      context "with unexisting directory with writable parent" do
        it "creates the output directory automatically" do
          unexisting_dir = output_dir + "/some_dir"
          expect {
            run_publisher_command("--token", "123", "--output-directory", unexisting_dir)
          }.to change {
            Dir.exists?(unexisting_dir)
          }.from(false).to(true)
        end

        it "creates the output directory automatically, even if deep" do
          unexisting_dir = output_dir + "/some/dir/deeply/nested"
          expect {
            run_publisher_command("--token", "123", "--output-directory", unexisting_dir)
          }.to change {
            Dir.exists?(unexisting_dir)
          }.from(false).to(true)
        end
      end

      context "with unexisting directory with UNwritable parent" do
        it "output an error message and stops" do
          unexisting_dir = "/usr/lib/some/dir"
          expect {
            run_publisher_expecting_exit("--token", "123", "--output-directory", unexisting_dir)
          }.to output(a_string_including("Error with --output-directory: the directory \"/usr/lib/some/dir\" can not be created because \"/usr/lib\" is not writable")).to_stdout
        end
      end

      context "with existing but unwritable directory" do
        it "output an error message and stops" do
          unwritable_dir = "/usr/lib"
          expect {
            run_publisher_expecting_exit("--token", "123", "--output-directory", unwritable_dir)
          }.to output(a_string_including("Error with --output-directory: the directory \"/usr/lib\" is not writable")).to_stdout
        end
      end

      context "with existing but is not a directory (it's a file)" do
        it "output an error message and stops" do
          file = output_dir + "/some_file"
          FileUtils.touch(file)
          expect {
            run_publisher_expecting_exit("--token", "123", "--output-directory", file)
          }.to output(a_string_including("Error with --output-directory: the file \"#{file}\" is not a directory")).to_stdout
        end
      end
    end
  end

  describe "--language=seleniumide" do
    def run_publisher_command(*extra_args)
      stub_request(:get, "https://hiptest.net/publication/123456789/project?future=1").
        to_return(body: File.read('samples/xml_input/Hiptest publisher.xml'))
      stub_request(:get, "https://hiptest.net/publication/123456789/leafless_tests?future=1").
        to_return(body: File.read('samples/xml_input/Hiptest automation.xml'))
      args = [
        "--language", "seleniumide",
        "--output-directory", output_dir,
        "--token", "123456789",
      ] + extra_args
      publisher = Hiptest::Publisher.new(args, listeners: [ErrorListener.new])
      publisher.run
    end

    it "does not trigger any error for unknown templates" do
      run_publisher_command
    end

    it "produces the files as expected" do
      # this is not very representative of how a selenium export should look like...
      run_publisher_command("--leafless-export", "--split-scenarios")
      expect_same_files("samples/expected_output/Hiptest publisher-selenium", output_dir)
    end
  end
end