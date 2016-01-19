# -*- coding: utf-8 -*-
#
#    Copyright (C) 2014 eNovance Inc. All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
import abc

import six

import tooz
from tooz import coordination


class _LockProxy(object):
    def __init__(self, lock, blocking=True):
        self.lock = lock
        self.blocking = blocking

    def __enter__(self):
        return self.lock.__enter__(self.blocking)

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.lock.__exit__(exc_type, exc_val, exc_tb)


@six.add_metaclass(abc.ABCMeta)
class Lock(object):
    def __init__(self, name):
        if not name:
            raise ValueError("Locks must be provided a name")
        self._name = name

    @property
    def name(self):
        return self._name

    def __call__(self, blocking=True):
        return _LockProxy(self, blocking)

    def __enter__(self, blocking=True):
        acquired = self.acquire(blocking)
        if not acquired:
            msg = u'Acquiring lock %s failed' % self.name
            raise coordination.LockAcquireFailed(msg)

        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()

    def is_still_owner(self):
        """Checks if the lock is still owned by the acquiree.

        :returns: returns true if still acquired (false if not) and
                  false if the lock was never acquired in the first place
                  or raises ``NotImplemented`` if not implemented.
        """
        raise tooz.NotImplemented

    @abc.abstractmethod
    def release(self):
        """Attempts to release the lock, returns true if released.

        The behavior of releasing a lock which was not acquired in the first
        place is undefined (it can range from harmless to releasing some other
        users lock)..

        :returns: returns true if released (false if not)
        :rtype: bool
        """

    @abc.abstractmethod
    def acquire(self, blocking=True):
        """Attempts to acquire the lock.

        :param blocking: If True, blocks until the lock is acquired. If False,
                         returns right away. Otherwise, the value is used as a
                         timeout value and the call returns maximum after this
                         number of seconds.
        :returns: returns true if acquired (false if not)
        :rtype: bool

        """
