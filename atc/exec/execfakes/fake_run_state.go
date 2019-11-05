// Code generated by counterfeiter. DO NOT EDIT.
package execfakes

import (
	"sync"

	"github.com/concourse/concourse/atc"
	"github.com/concourse/concourse/atc/exec"
	"github.com/concourse/concourse/atc/exec/artifact"
)

type FakeRunState struct {
	ArtifactsStub        func() *artifact.Repository
	artifactsMutex       sync.RWMutex
	artifactsArgsForCall []struct {
	}
	artifactsReturns struct {
		result1 *artifact.Repository
	}
	artifactsReturnsOnCall map[int]struct {
		result1 *artifact.Repository
	}
	ResultStub        func(atc.PlanID, interface{}) bool
	resultMutex       sync.RWMutex
	resultArgsForCall []struct {
		arg1 atc.PlanID
		arg2 interface{}
	}
	resultReturns struct {
		result1 bool
	}
	resultReturnsOnCall map[int]struct {
		result1 bool
	}
	StoreResultStub        func(atc.PlanID, interface{})
	storeResultMutex       sync.RWMutex
	storeResultArgsForCall []struct {
		arg1 atc.PlanID
		arg2 interface{}
	}
	invocations      map[string][][]interface{}
	invocationsMutex sync.RWMutex
}

func (fake *FakeRunState) Artifacts() *artifact.Repository {
	fake.artifactsMutex.Lock()
	ret, specificReturn := fake.artifactsReturnsOnCall[len(fake.artifactsArgsForCall)]
	fake.artifactsArgsForCall = append(fake.artifactsArgsForCall, struct {
	}{})
	fake.recordInvocation("Artifacts", []interface{}{})
	fake.artifactsMutex.Unlock()
	if fake.ArtifactsStub != nil {
		return fake.ArtifactsStub()
	}
	if specificReturn {
		return ret.result1
	}
	fakeReturns := fake.artifactsReturns
	return fakeReturns.result1
}

func (fake *FakeRunState) ArtifactsCallCount() int {
	fake.artifactsMutex.RLock()
	defer fake.artifactsMutex.RUnlock()
	return len(fake.artifactsArgsForCall)
}

func (fake *FakeRunState) ArtifactsCalls(stub func() *artifact.Repository) {
	fake.artifactsMutex.Lock()
	defer fake.artifactsMutex.Unlock()
	fake.ArtifactsStub = stub
}

func (fake *FakeRunState) ArtifactsReturns(result1 *artifact.Repository) {
	fake.artifactsMutex.Lock()
	defer fake.artifactsMutex.Unlock()
	fake.ArtifactsStub = nil
	fake.artifactsReturns = struct {
		result1 *artifact.Repository
	}{result1}
}

func (fake *FakeRunState) ArtifactsReturnsOnCall(i int, result1 *artifact.Repository) {
	fake.artifactsMutex.Lock()
	defer fake.artifactsMutex.Unlock()
	fake.ArtifactsStub = nil
	if fake.artifactsReturnsOnCall == nil {
		fake.artifactsReturnsOnCall = make(map[int]struct {
			result1 *artifact.Repository
		})
	}
	fake.artifactsReturnsOnCall[i] = struct {
		result1 *artifact.Repository
	}{result1}
}

func (fake *FakeRunState) Result(arg1 atc.PlanID, arg2 interface{}) bool {
	fake.resultMutex.Lock()
	ret, specificReturn := fake.resultReturnsOnCall[len(fake.resultArgsForCall)]
	fake.resultArgsForCall = append(fake.resultArgsForCall, struct {
		arg1 atc.PlanID
		arg2 interface{}
	}{arg1, arg2})
	fake.recordInvocation("Result", []interface{}{arg1, arg2})
	fake.resultMutex.Unlock()
	if fake.ResultStub != nil {
		return fake.ResultStub(arg1, arg2)
	}
	if specificReturn {
		return ret.result1
	}
	fakeReturns := fake.resultReturns
	return fakeReturns.result1
}

func (fake *FakeRunState) ResultCallCount() int {
	fake.resultMutex.RLock()
	defer fake.resultMutex.RUnlock()
	return len(fake.resultArgsForCall)
}

func (fake *FakeRunState) ResultCalls(stub func(atc.PlanID, interface{}) bool) {
	fake.resultMutex.Lock()
	defer fake.resultMutex.Unlock()
	fake.ResultStub = stub
}

func (fake *FakeRunState) ResultArgsForCall(i int) (atc.PlanID, interface{}) {
	fake.resultMutex.RLock()
	defer fake.resultMutex.RUnlock()
	argsForCall := fake.resultArgsForCall[i]
	return argsForCall.arg1, argsForCall.arg2
}

func (fake *FakeRunState) ResultReturns(result1 bool) {
	fake.resultMutex.Lock()
	defer fake.resultMutex.Unlock()
	fake.ResultStub = nil
	fake.resultReturns = struct {
		result1 bool
	}{result1}
}

func (fake *FakeRunState) ResultReturnsOnCall(i int, result1 bool) {
	fake.resultMutex.Lock()
	defer fake.resultMutex.Unlock()
	fake.ResultStub = nil
	if fake.resultReturnsOnCall == nil {
		fake.resultReturnsOnCall = make(map[int]struct {
			result1 bool
		})
	}
	fake.resultReturnsOnCall[i] = struct {
		result1 bool
	}{result1}
}

func (fake *FakeRunState) StoreResult(arg1 atc.PlanID, arg2 interface{}) {
	fake.storeResultMutex.Lock()
	fake.storeResultArgsForCall = append(fake.storeResultArgsForCall, struct {
		arg1 atc.PlanID
		arg2 interface{}
	}{arg1, arg2})
	fake.recordInvocation("StoreResult", []interface{}{arg1, arg2})
	fake.storeResultMutex.Unlock()
	if fake.StoreResultStub != nil {
		fake.StoreResultStub(arg1, arg2)
	}
}

func (fake *FakeRunState) StoreResultCallCount() int {
	fake.storeResultMutex.RLock()
	defer fake.storeResultMutex.RUnlock()
	return len(fake.storeResultArgsForCall)
}

func (fake *FakeRunState) StoreResultCalls(stub func(atc.PlanID, interface{})) {
	fake.storeResultMutex.Lock()
	defer fake.storeResultMutex.Unlock()
	fake.StoreResultStub = stub
}

func (fake *FakeRunState) StoreResultArgsForCall(i int) (atc.PlanID, interface{}) {
	fake.storeResultMutex.RLock()
	defer fake.storeResultMutex.RUnlock()
	argsForCall := fake.storeResultArgsForCall[i]
	return argsForCall.arg1, argsForCall.arg2
}

func (fake *FakeRunState) Invocations() map[string][][]interface{} {
	fake.invocationsMutex.RLock()
	defer fake.invocationsMutex.RUnlock()
	fake.artifactsMutex.RLock()
	defer fake.artifactsMutex.RUnlock()
	fake.resultMutex.RLock()
	defer fake.resultMutex.RUnlock()
	fake.storeResultMutex.RLock()
	defer fake.storeResultMutex.RUnlock()
	copiedInvocations := map[string][][]interface{}{}
	for key, value := range fake.invocations {
		copiedInvocations[key] = value
	}
	return copiedInvocations
}

func (fake *FakeRunState) recordInvocation(key string, args []interface{}) {
	fake.invocationsMutex.Lock()
	defer fake.invocationsMutex.Unlock()
	if fake.invocations == nil {
		fake.invocations = map[string][][]interface{}{}
	}
	if fake.invocations[key] == nil {
		fake.invocations[key] = [][]interface{}{}
	}
	fake.invocations[key] = append(fake.invocations[key], args)
}

var _ exec.RunState = new(FakeRunState)