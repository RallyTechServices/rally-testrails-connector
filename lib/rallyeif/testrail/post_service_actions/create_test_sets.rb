# Copyright 2001-2015 Rally Software Development Corp. All Rights Reserved.

module RallyEIF
  module WRK
    module PostServiceActions

      class CreateTestSets < PostServiceAction

        def setup(action_config, rally_conn, other_conn)
          super(action_config, rally_conn, other_conn)
          if other_conn.artifact_type != :testresult
            msg = "CreateTestSets will only work with the TestResult Artifact in TestRail"
            raise UnrecoverableException.new(msg, self)
          end
          if (rally_conn.artifact_type != :testcaseresult)
            msg = "CreateTestSets will only work with the TestCaseResult Artifact in Rally"
            raise UnrecoverableException.new(msg, self)
          end
        end

        def post_copy_to_rally_action(item_list)
          process_results(item_list)
        end

        def post_update_to_rally_action(item_list)
          process_results(item_list)
        end

        def find_rally_test_case_by_oid(oid)
          begin
            query = RallyAPI::RallyQuery.new()
            query.type       = 'testcase'
            query.workspace  = @rally_connection.workspace
            #query.fetch      = "true"
            query.fetch      = "FormattedID,Name,Iteration,Project,WorkProduct,ObjectID"
            query.limit      = 1
  
            base_string = "( ObjectID = #{oid} )"
  
            query.query_string = base_string
            RallyLogger.debug(self, "Rally using query: #{query.query_string}")
  
            query_result = @rally_connection.rally.find(query)
  
          rescue Exception => ex
            raise UnrecoverableException.copy(ex, self)
          end
          
          return query_result.first
        end
        
        def find_rally_test_set_by_name(name)
          begin
            query = RallyAPI::RallyQuery.new()
            query.type       = 'testset'
            query.workspace  = @rally_connection.workspace
            query.fetch      = "FormattedID,Name,Iteration,Project,ObjectID"
            query.limit      = 1
  
            base_string = "( Name contains \"#{name}\" )"
  
            query.query_string = base_string
            RallyLogger.debug(self, "Rally using query: #{query.query_string}")
  
            query_result = @rally_connection.rally.find(query)
  
          rescue Exception => ex
            raise UnrecoverableException.copy(ex, self)
          end
          
          return query_result.first
        end
        
        def create_rally_test_set(name,rally_test_case)
          RallyLogger.debug(self, "Creating a TestSet at #{name}")
          workproduct = rally_test_case['WorkProduct']
          new_test_set = nil
          
          if workproduct.nil?
            RallyLogger.info(self, "Test Case is not associated with a Story")
          else
            # workproduct = @rally_connection.rally.read("hierarchicalrequirement", workproduct['ObjectID'])
            iteration = workproduct['Iteration']
            project = workproduct['Project']
            RallyLogger.debug(self, "#{iteration}, #{project}")
            ts = { "Name" => name, "Iteration" => iteration, "Project" => project }
            new_test_set = @rally_connection.rally.create('testset',ts)
          end
          return new_test_set
        end
        
        def add_testcase_to_test_set(rally_test_case,rally_test_set)
          RallyLogger.info(self, "Adding #{rally_test_case} to #{rally_test_set}")
          
          test_set = @rally_connection.rally.read("testset", rally_test_set['ObjectID'])
          
          associated_test_cases = test_set['TestCases'] || []
          associated_test_cases = associated_test_cases.push(rally_test_case)
          
          refs = []
            
          associated_test_cases.each do |tc|
            refs.push({"_ref"=> tc['_ref']})
          end

          fields = { "TestCases" => refs }
          rally_test_set.update(fields)
        end
        
        def process_results(tr_testresults_list)
          RallyLogger.debug(self, "Running post process to associate test runs to test sets in Rally...")
         
          runs = @other_connection.find_test_runs()
          
          runs.each do |run|
            run_name = "#{run['id']}: #{run['name']} #{run['config']}"
            
            tests = @other_connection.find_test_for_run(run['id'])
            
            rally_test_set = nil

            tests.each do |test|
              # RallyLogger.debug(self, "--Test: #{test}")
              rally_oid = test["custom_#{@other_connection.external_id_field.downcase}"]

              if !rally_oid.nil?
                rally_test_case = find_rally_test_case_by_oid(rally_oid)
                if !rally_test_case.nil?
                  rally_test_set = find_rally_test_set_by_name(run_name)
                  if rally_test_set.nil?
                    rally_test_set = create_rally_test_set(run_name,rally_test_case)
                  end
                  if !rally_test_set.nil?
                    add_testcase_to_test_set(rally_test_case,rally_test_set)
                  end
                else
                  RallyLogger.info(self, "Couldn't find Rally test case for: #{test['case_id']}")
                end

              else
                RallyLogger.info(self, "Skip test case that's not connected to Rally: #{test['case_id']}")
              end
            end
          end
          
          RallyLogger.info(self,"Associate TestResult with the TestSet")
          tr_testresults_list.each do |testresult|
            RallyLogger.debug(self,"testresult: #{testresult}")
            RallyLogger.debug(self,"test: #{testresult['_test']['run_id']}")
            rally_test_set = find_rally_test_set_by_name("#{testresult['_test']['run_id']}:")
            
            rally_result = @rally_connection.find_result_with_build(testresult['id'])
            if !rally_result.nil?
              fields = {"TestSet"=>rally_test_set}
              rally_result.update(fields)
            else
              RallyLogger.info(self, "No result found in Rally: #{testresult['id']}")
            end
          end
          
          RallyLogger.debug(self, "Completed running post process to associate test runs to test sets in Rally.")
        end

      end

    end
  end
end