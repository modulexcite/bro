#ifndef BloomFilter_h
#define BloomFilter_h

#include <vector>
#include "BitVector.h"
#include "Hasher.h"

namespace probabilistic {

class CounterVector;

/**
 * The abstract base class for Bloom filters.
 */
class BloomFilter : public SerialObj {
public:
  // At this point we won't let the user choose the hasher, but we might
  // open up the interface in the future.
  virtual ~BloomFilter();

  /**
   * Adds an element of type T to the Bloom filter.
   * @param x The element to add
   */
  template <typename T>
  void Add(const T& x)
    {
    AddImpl((*hasher_)(x));
    }

  /**
   * Retrieves the associated count of a given value.
   *
   * @param x The value of type `T` to check.
   *
   * @return The counter associated with *x*.
   */
  template <typename T>
  size_t Count(const T& x) const
    {
    return CountImpl((*hasher_)(x));
    }

  bool Serialize(SerialInfo* info) const;
  static BloomFilter* Unserialize(UnserialInfo* info);

protected:
  DECLARE_ABSTRACT_SERIAL(BloomFilter);

	BloomFilter();

	/**
	 * Constructs a Bloom filter.
	 *
	 * @param hasher The hasher to use for this Bloom filter.
	 */
  BloomFilter(const Hasher* hasher);

  virtual void AddImpl(const Hasher::digest_vector& hashes) = 0;
  virtual size_t CountImpl(const Hasher::digest_vector& hashes) const = 0;

  const Hasher* hasher_;
};

/**
 * A basic Bloom filter.
 */
class BasicBloomFilter : public BloomFilter {
public:
  /**
   * Computes the number of cells based a given false-positive rate and
   * capacity. In the literature, this parameter often has the name *M*.
   *
   * @param fp The false-positive rate.
   *
   * @param capacity The number of exepected elements.
   *
   * Returns: The number cells needed to support a false-positive rate of *fp*
   * with at most *capacity* elements.
   */
  static size_t M(double fp, size_t capacity);

  /**
   * Computes the optimal number of hash functions based on the number cells
   * and expected number of elements.
   *
   * @param cells The number of cells (*m*).
   *
   * @param capacity The maximum number of elements.
   *
   * Returns: the optimal number of hash functions for a false-positive rate of
   * *fp* for at most *capacity* elements.
   */
  static size_t K(size_t cells, size_t capacity);

  static BasicBloomFilter* Merge(const BasicBloomFilter* x,
                                 const BasicBloomFilter* y);

  /**
   * Constructs a basic Bloom filter with a given number of cells and capacity.
   */
  BasicBloomFilter(const Hasher* hasher, size_t cells);

protected:
  DECLARE_SERIAL(BasicBloomFilter);

  BasicBloomFilter();

  virtual void AddImpl(const Hasher::digest_vector& h);
  virtual size_t CountImpl(const Hasher::digest_vector& h) const;

private:
  BitVector* bits_;
};

/**
 * A counting Bloom filter.
 */
class CountingBloomFilter : public BloomFilter {
public:
  static CountingBloomFilter* Merge(const CountingBloomFilter* x,
                                    const CountingBloomFilter* y);

  CountingBloomFilter(const Hasher* hasher, size_t cells, size_t width);

protected:
  DECLARE_SERIAL(CountingBloomFilter);

  CountingBloomFilter();

  virtual void AddImpl(const Hasher::digest_vector& h);
  virtual size_t CountImpl(const Hasher::digest_vector& h) const;

private:
  CounterVector* cells_;
};

}

#endif
